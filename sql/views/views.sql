-- =====================================================================
-- PROJETO DE BANCO DE DADOS 2026/2 - UFF - Prof. Marcos Bedo
-- create_views.sql
-- =====================================================================
-- Execute depois de create_constraints.sql. Se for rodar ANTES do
-- insert_data.sql, as materializadas nascem vazias: rode
--     SELECT fn_refresh_views();
-- depois da carga (e sempre que quiser os números atualizados).
--
-- Convenção: doações com status = 'recusado' NÃO contam como receita.
-- (Decisão de modelagem a confirmar com a equipe.)
-- =====================================================================

SET search_path TO public;

DROP VIEW              IF EXISTS vw_canal_faturamento;
DROP VIEW              IF EXISTS vw_canal_doacoes;        
DROP VIEW              IF EXISTS vw_video_comentarios;   
DROP MATERIALIZED VIEW IF EXISTS mv_canal_doacoes;
DROP MATERIALIZED VIEW IF EXISTS mv_video_comentarios;

-- ---------------------------------------------------------------------
-- V1) mv_video_comentarios  [MATERIALIZADA]
-- ---------------------------------------------------------------------
-- O que faz: comentários online/offline/total por vídeo.
-- Por que existe: base das consultas 2 e 3. O LEFT JOIN mantém vídeos
-- sem comentário com zero, necessário para a média de interações por
-- vídeo (consulta 3) não ignorar vídeos "zerados".
-- Por que materializada: percorre Comentario inteira (a tabela mais
-- escrita) agrupando por vídeo, e é lida por duas consultas. Pré-
-- calcular evita refazer o agrupamento a cada chamada.
CREATE MATERIALIZED VIEW mv_video_comentarios AS
SELECT v.id_video,
       v.id_canal,
       v.titulo,
       COUNT(c.id_comentario) FILTER (WHERE c.coment_on)     AS qtd_online,
       COUNT(c.id_comentario) FILTER (WHERE NOT c.coment_on) AS qtd_offline,
       COUNT(c.id_comentario)                                AS qtd_total
  FROM Video v
  LEFT JOIN Comentario c ON c.id_video = v.id_video
 GROUP BY v.id_video, v.id_canal, v.titulo
WITH DATA;

-- ---------------------------------------------------------------------
-- V2) mv_canal_doacoes  [MATERIALIZADA]
-- ---------------------------------------------------------------------
-- O que faz: total e quantidade de doações por canal.
-- Por que existe: base das consultas 4, 7, 10 e 11. qtd_comentarios_
-- com_doacao (comentários distintos) serve à média "por comentário"
-- da consulta 4, já que um comentário pode ter várias doações (seq_pg).
-- Por que materializada: é a consulta mais cara do projeto (JOIN em
-- cadeia Doacao -> Comentario -> Video + COUNT DISTINCT) e alimenta
-- quatro consultas, inclusive a de faturamento total.
CREATE MATERIALIZED VIEW mv_canal_doacoes AS
SELECT vid.id_canal,
       COUNT(*)                        AS qtd_doacoes,
       COUNT(DISTINCT d.id_comentario) AS qtd_comentarios_com_doacao,
       SUM(d.valor)                    AS total_doacoes
  FROM Doacao d
  JOIN Comentario c ON c.id_comentario = d.id_comentario
  JOIN Video vid     ON vid.id_video    = c.id_video
 WHERE d.status <> 'recusado'
 GROUP BY vid.id_canal
WITH DATA;

-- ---------------------------------------------------------------------
-- V3) vw_canal_patrocinio  [VIRTUAL]
-- ---------------------------------------------------------------------
-- O que faz: total de patrocínio vigente por canal (consultas 8 e 11).
-- Por que virtual: Patrocinio é pequena (~1.800 linhas) e o índice
-- idx_patrocinio_canal (id_canal) INCLUDE (valor) já permite resolver
-- o SUM só no índice. Materializar não ganharia nada e ainda criaria
-- defasagem. Como não há histórico, toda linha já é "vigente".
CREATE OR REPLACE VIEW vw_canal_patrocinio AS
SELECT p.id_canal,
       COUNT(*)     AS qtd_patrocinadores,
       SUM(p.valor) AS total_patrocinio
  FROM Patrocinio p
 GROUP BY p.id_canal;

-- ---------------------------------------------------------------------
-- V4) vw_canal_membros  [VIRTUAL]
-- ---------------------------------------------------------------------
-- O que faz: aporte mensal de membros por canal (consultas 9 e 11).
-- Precisa do JOIN Inscricao -> NivelCanal porque o valor do nível é
-- definido por canal.
-- Por que virtual: Inscricao (~7.000) e NivelCanal (9.000) são médias/
-- pequenas, o idx_inscricao_canal já apoia o agrupamento, e membros
-- entram e saem sem aviso: manter o dado sempre fresco vale mais do
-- que o ganho de milissegundos.
CREATE OR REPLACE VIEW vw_canal_membros AS
SELECT i.id_canal,
       COUNT(*)     AS qtd_membros,
       SUM(n.valor) AS total_mensal
  FROM Inscricao i
  JOIN NivelCanal n ON n.id_nivel_canal = i.id_nivel_canal
 GROUP BY i.id_canal;

-- ---------------------------------------------------------------------
-- V5) vw_canal_faturamento  [VIRTUAL]
-- ---------------------------------------------------------------------
-- O que faz: consolida as três fontes de receita por canal
-- (consulta 11). LEFT JOIN + COALESCE mantêm canais sem alguma fonte.
-- Por que virtual: é só um JOIN de ~1.800 linhas sobre resultados já
-- agregados (uma MV e duas views leves). O trabalho pesado já foi
-- feito em mv_canal_doacoes.
-- ATENÇÃO: a coluna "doacoes" vem da materializada, então pode estar
-- defasada até o próximo refresh; patrocinio e membros_mensal são
-- sempre atuais.
CREATE OR REPLACE VIEW vw_canal_faturamento AS
SELECT c.id_canal,
       c.nome                          AS canal,
       COALESCE(p.total_patrocinio, 0) AS patrocinio,
       COALESCE(m.total_mensal, 0)     AS membros_mensal,
       COALESCE(d.total_doacoes, 0)    AS doacoes,
       COALESCE(p.total_patrocinio, 0)
     + COALESCE(m.total_mensal, 0)
     + COALESCE(d.total_doacoes, 0)    AS faturamento_total
  FROM Canal c
  LEFT JOIN vw_canal_patrocinio p ON p.id_canal = c.id_canal
  LEFT JOIN vw_canal_membros    m ON m.id_canal = c.id_canal
  LEFT JOIN mv_canal_doacoes    d ON d.id_canal = c.id_canal;

-- ---------------------------------------------------------------------
-- Atualização das materializadas
-- ---------------------------------------------------------------------
-- Escolha: refresh MANUAL, em vez de trigger. Um trigger que desse
-- REFRESH a cada INSERT em Comentario/Doacao (as tabelas mais
-- escritas) travaria a escrita e anularia o ganho de desempenho.
-- Use: SELECT fn_refresh_views();  -- após cargas ou antes de relatórios
-- (REFRESH simples bloqueia leituras durante o recálculo, aceitável
-- neste volume; CONCURRENTLY exigiria índices únicos nas MVs e
-- consumiria o limite de 5 índices do projeto.)
CREATE OR REPLACE FUNCTION fn_refresh_views() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    REFRESH MATERIALIZED VIEW mv_video_comentarios;
    REFRESH MATERIALIZED VIEW mv_canal_doacoes;
END $$;

-- =====================================================================
-- Views consideradas e descartadas (para justificar no relatório):
--  - vw_plataforma_streamers: a consulta 12 agrupa Canal por
--    nro_plataforma direto; coberta por idx_canal_plataforma.
--  - vw_usuario_membros: a consulta 6 é uma única junção
--    Inscricao -> NivelCanal agrupando por nick_membro; uma view
--    separada duplicaria lógica sem ganho real.
--  - Materializar V3, V4 e V5: ganho desprezível no volume do projeto
--    (1.000-10.000 linhas) e custo de dado velho em fontes de receita
--    que mudam de forma independente.
-- =====================================================================