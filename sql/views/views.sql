-- =====================================================================
-- PROJETO DE BANCO DE DADOS 2026/2 - UFF - Prof. Marcos Bedo
-- create_views.sql
-- =====================================================================
-- Execute depois de create_constraints.sql.
-- =====================================================================

SET search_path TO public;

-- ---------------------------------------------------------------------
-- V1) vw_video_comentarios
-- ---------------------------------------------------------------------
-- Justificativa: separa comentários online/offline/total por vídeo.
-- Usa LEFT JOIN para que vídeos sem nenhum comentário apareçam com
-- zero, o que é necessário para a média de interações por vídeo,
-- não ficar enviesada ignorando vídeos "zerados".
-- Reaproveitada nas consultas 2 e 3.
CREATE OR REPLACE VIEW vw_video_comentarios AS
SELECT v.id_video,
       v.id_canal,
       v.titulo,
       COUNT(c.id_comentario) FILTER (WHERE c.coment_on)     AS qtd_online,
       COUNT(c.id_comentario) FILTER (WHERE NOT c.coment_on) AS qtd_offline,
       COUNT(c.id_comentario)                                AS qtd_total
  FROM Video v
  LEFT JOIN Comentario c ON c.id_video = v.id_video
 GROUP BY v.id_video, v.id_canal, v.titulo;

-- ---------------------------------------------------------------------
-- V2) vw_canal_doacoes
-- ---------------------------------------------------------------------
-- Justificativa: agrega doações por canal percorrendo o caminho
-- Doacao -> Comentario -> Video -> Canal, que é caro de reescrever em
-- toda consulta que precisa desse total (consultas 4, 7, 10 e 11).
CREATE OR REPLACE VIEW vw_canal_doacoes AS
SELECT vid.id_canal,
       COUNT(*)                          AS qtd_doacoes,
       COUNT(DISTINCT d.id_comentario)   AS qtd_comentarios_com_doacao,
       SUM(d.valor)                      AS total_doacoes
  FROM Doacao d
  JOIN Comentario c ON c.id_comentario = d.id_comentario
  JOIN Video vid     ON vid.id_video    = c.id_video
 WHERE d.status <> 'recusado'
 GROUP BY vid.id_canal;

-- ---------------------------------------------------------------------
-- V3) vw_canal_patrocinio
-- ---------------------------------------------------------------------
-- Justificativa: total de patrocínio vigente por canal. Evita
-- repetir o GROUP BY nas consultas 8 (top-k patrocínio) e 11
-- (faturamento total).
CREATE OR REPLACE VIEW vw_canal_patrocinio AS
SELECT p.id_canal,
       COUNT(*)     AS qtd_patrocinadores,
       SUM(p.valor) AS total_patrocinio
  FROM Patrocinio p
 GROUP BY p.id_canal;

-- ---------------------------------------------------------------------
-- V4) vw_canal_membros
-- ---------------------------------------------------------------------
-- Justificativa: soma o valor mensal recebido de membros por canal.
-- Precisa do JOIN Inscricao -> NivelCanal porque o valor do nível é
-- definido por canal. Reaproveitada nas consultas 6, 9 e 11.
CREATE OR REPLACE VIEW vw_canal_membros AS
SELECT i.id_canal,
       COUNT(*)     AS qtd_membros,
       SUM(n.valor) AS total_mensal
  FROM Inscricao i
  JOIN NivelCanal n ON n.id_nivel_canal = i.id_nivel_canal
 GROUP BY i.id_canal;

-- ---------------------------------------------------------------------
-- V5) vw_canal_faturamento
-- ---------------------------------------------------------------------
-- Justificativa: consolida as três fontes de receita (patrocínio,
-- membros, doações) por canal, exigidas juntas na consulta 11. Reusa
-- V2, V3 e V4 em vez de repetir os três agrupamentos. LEFT JOIN +
-- COALESCE garantem que um canal sem alguma das fontes não seja
-- excluído do resultado.
CREATE OR REPLACE VIEW vw_canal_faturamento AS
SELECT c.id_canal,
       c.nome                                AS canal,
       COALESCE(p.total_patrocinio, 0)       AS patrocinio,
       COALESCE(m.total_mensal, 0)           AS membros_mensal,
       COALESCE(d.total_doacoes, 0)          AS doacoes,
       COALESCE(p.total_patrocinio, 0)
     + COALESCE(m.total_mensal, 0)
     + COALESCE(d.total_doacoes, 0)          AS faturamento_total
  FROM Canal c
  LEFT JOIN vw_canal_patrocinio p ON p.id_canal = c.id_canal
  LEFT JOIN vw_canal_membros    m ON m.id_canal = c.id_canal
  LEFT JOIN vw_canal_doacoes    d ON d.id_canal = c.id_canal;