-- =====================================================================
-- PROJETO DE BANCO DE DADOS 2026/2 - UFF - Prof. Marcos Bedo
-- indices.sql
-- =====================================================================
-- Observação geral: toda PRIMARY KEY e UNIQUE já cria um índice
-- automaticamente no Postgres. Em índices compostos, apenas a coluna
-- mais à esquerda se beneficia de buscas isoladas por ela (regra do
-- prefixo). Os 5 índices abaixo cobrem colunas de junção/filtro que
-- as consultas do enunciado usam e que NÃO ficam cobertas por nenhum
-- índice automático existente.
-- =====================================================================

SET search_path TO public;

-- ---------------------------------------------------------------------
-- 1) Canal(nick_streamer)
-- ---------------------------------------------------------------------
-- Justificativa: nick_streamer é FK mas não é a coluna mais à esquerda
-- de nenhuma UNIQUE existente (unq_canal_plataforma é (nome,
-- nro_plataforma)). É usada nas consultas 1 ("streamers com mais
-- vídeos") e 3 (filtro opcional por streamer) para localizar todos os
-- canais de um streamer. Sem esse índice, essas buscas fariam
-- sequential scan em Canal inteira. Overhead de escrita é baixo:
-- Canal tem poucos INSERTs comparado a Comentario/Doacao.
CREATE INDEX idx_canal_streamer ON Canal (nick_streamer);

-- ---------------------------------------------------------------------
-- 2) Canal(nro_plataforma)
-- ---------------------------------------------------------------------
-- Justificativa: mesma lógica do índice 1, mas para o filtro opcional
-- por plataforma, usado nas consultas 1 e 12 ("top-k plataformas por
-- streamers e canais"). nro_plataforma também não é coluna mais à
-- esquerda em nenhuma UNIQUE de Canal.
CREATE INDEX idx_canal_plataforma ON Canal (nro_plataforma);

-- ---------------------------------------------------------------------
-- 3) Patrocinio(id_canal) incluindo valor
-- ---------------------------------------------------------------------
-- Justificativa: a UNIQUE existente é (nro_empresa, id_canal), então
-- buscas/agrupamentos por id_canal isolado (consulta 8: "k canais que
-- mais recebem patrocínio") não usam essa UNIQUE eficientemente.
-- Colocamos valor no índice (índice de cobertura) para permitir que o
-- agregado SUM(valor) por canal seja resolvido só com o índice, sem
-- tocar a tabela. Overhead de escrita é aceitável: Patrocinio só muda
-- quando um patrocínio é criado/encerrado (baixa frequência).
CREATE INDEX idx_patrocinio_canal ON Patrocinio (id_canal) INCLUDE (valor);

-- ---------------------------------------------------------------------
-- 4) Inscricao(id_canal) incluindo id_nivel_canal
-- ---------------------------------------------------------------------
-- Justificativa: a UNIQUE existente é (nick_membro, id_canal), então
-- agrupar por canal (consulta 9: "k canais que mais recebem aportes de
-- membros") não é servido eficientemente por ela. Incluímos
-- id_nivel_canal para resolver o JOIN com NivelCanal (valor mensal)
-- usando o índice. Overhead moderado, mas Inscricao só muda quando um
-- membro entra/sai (bem menos frequente que Comentario/Doacao).
CREATE INDEX idx_inscricao_canal ON Inscricao (id_canal) INCLUDE (id_nivel_canal);

-- ---------------------------------------------------------------------
-- 5) Comentario(id_video, coment_on)
-- ---------------------------------------------------------------------
-- Justificativa: a UNIQUE existente é (id_video, nick_usuario, seq),
-- que já cobre buscas por id_video isolado, mas não ajuda a separar
-- comentários online/offline sem ler a tabela. A consulta 2 pede
-- explicitamente "quantidade de comentários online, offline e total"
-- por vídeo, e a consulta 3 soma isso por canal. Um índice composto
-- (id_video, coment_on) permite contar por grupo sem sequential scan.
-- É o índice de maior custo de escrita da lista (Comentario é a
-- tabela mais escrita do banco, junto com Doacao), mas o ganho nas
-- consultas 2 e 3 -- que são agregações pedidas explicitamente -- 
-- compensa o overhead.
CREATE INDEX idx_comentario_video_online ON Comentario (id_video, coment_on);

-- =====================================================================
-- Índices considerados e descartados (para justificar no relatório):
--  - Doacao(id_comentario): já coberto pela UNIQUE(id_comentario,
--    seq_pg) existente (coluna mais à esquerda).
--  - Video(id_canal): já coberto pela UNIQUE(id_canal, titulo, dataH)
--    existente.
--  - Comentario(nick_usuario): nenhuma das 12 consultas agrega por
--    usuário comentarista, só por vídeo/canal -- não justificaria o
--    overhead extra na tabela mais escrita do banco.
-- =====================================================================
