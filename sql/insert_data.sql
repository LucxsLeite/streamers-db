-- =====================================================================
-- PROJETO DE BANCO DE DADOS 2026/2 - UFF - Prof. Marcos Bedo
-- insert_data.sql
-- =====================================================================
-- Execute depois de create_constraints.sql, numa
-- base LIMPA (recém-criada). Dados 100% sintéticos/fictícios, conforme
-- permitido pelo enunciado ("dados artificiais serão aceitos").
--
-- IMPORTANTE - LEIA ANTES DE RODAR:
-- Este script assume que os identificadores GENERATED ALWAYS AS
-- IDENTITY (Empresa.nro, Plataforma.nro, Canal.id_canal, Video.id_video,
-- Comentario.id_comentario, Doacao.id_doacao, NivelCanal.id_nivel_canal)
-- são gerados de forma CONTÍNUA a partir de 1, sem lacunas -- por isso
-- os blocos abaixo escolhem FKs aleatórias "por fórmula" (ex.:
-- 1+floor(random()*1800) para referenciar um Canal), em vez de
-- subconsultas, por performance. Isso só é válido se:
--   (a) o script rodar em uma base recém-criada (sem dados prévios), e
--   (b) rodar UMA ÚNICA VEZ, do início ao fim, sem interrupções.
-- Se precisar rodar de novo, refaça create_database.sql do zero antes,
-- ou rode:
--   TRUNCATE TABLE BitCoin, PayPal, CartaoCredito, MecanismoPlat,
--     Doacao, Comentario, Participa, Video, Inscricao, NivelCanal,
--     Patrocinio, Canal, EmpresaPais, StreamerPais, PlataformaUsuario,
--     Usuario, Pais, Plataforma, Conversao, Empresa
--     RESTART IDENTITY CASCADE;
--
-- Volumetria escolhida (todas dentro de 1.000-10.000, item mandatório 1):
--   Empresa 1200 | Conversao 1000 | Plataforma 1000 | Pais 1000
--   Usuario 5000 | PlataformaUsuario ~6000 | StreamerPais ~1500
--   EmpresaPais ~1200 | Canal 1800 | NivelCanal 9000 (5 por canal)
--   Patrocinio ~1800 | Inscricao ~7000 | Video 5000 | Participa ~3000
--   Comentario 9000 | Doacao 4800 | BitCoin/PayPal/CartaoCredito/
--   MecanismoPlat 1200 cada (4800 / 4 formas de pagamento)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) Empresa (1200) -- sem FK
-- ---------------------------------------------------------------------
INSERT INTO Empresa (nome, nome_fantasia)
SELECT 'Empresa ' || i, 'Fantasia ' || i
FROM generate_series(1, 1200) AS i;

-- ---------------------------------------------------------------------
-- 2) Conversao (1000) -- sem FK. moeda sintética garante unicidade.
-- ---------------------------------------------------------------------
INSERT INTO Conversao (moeda, nome, fator_conver)
SELECT 'CUR' || lpad(i::text, 4, '0'),
       'Moeda Fictícia ' || i,
       round((random() * 4.5 + 0.05)::numeric, 6)
FROM generate_series(1, 1000) AS i;

-- ---------------------------------------------------------------------
-- 3) Plataforma (1000) -- FK empresa_fund/empresa_respo -> Empresa(1..1200)
-- ---------------------------------------------------------------------
INSERT INTO Plataforma (nome, qtd_users, empresa_fund, empresa_respo, data_fund)
SELECT 'Plataforma ' || i,
       (floor(random() * 5000000))::int,
       (1 + floor(random() * 1200))::bigint,
       (1 + floor(random() * 1200))::bigint,
       CURRENT_DATE - (floor(random() * 7300))::int
FROM generate_series(1, 1000) AS i;

-- ---------------------------------------------------------------------
-- 4) Pais (1000) -- FK moeda -> Conversao(1..1000). DDI sintético = i.
-- ---------------------------------------------------------------------
INSERT INTO Pais (DDI, nome, moeda)
SELECT i,
       'País Fictício ' || i,
       'CUR' || lpad((1 + floor(random() * 1000))::int::text, 4, '0')
FROM generate_series(1, 1000) AS i;

-- ---------------------------------------------------------------------
-- 5) Usuario (5000) -- FK pais_residencia -> Pais(1..1000)
--    nick = 'userN' (N = 1..5000) -- convenção usada no restante do script
--    para localizar usuários por fórmula sem subconsulta.
-- ---------------------------------------------------------------------
INSERT INTO Usuario (nick, email, data_nasc, telefone, end_postal, pais_residencia)
SELECT 'user' || i,
       'user' || i || '@example.com',
       DATE '1970-01-01' + (floor(random() * 18250))::int,
       '+55' || lpad((floor(random() * 99999999999))::text, 11, '0'),
       'Rua Fictícia, ' || (1 + floor(random() * 9999))::int,
       (1 + floor(random() * 1000))::int
FROM generate_series(1, 5000) AS i;

-- ---------------------------------------------------------------------
-- 6) PlataformaUsuario (~6000) -- par aleatório (plataforma, usuario)
--    Gera 6300 candidatos e descarta colisões via ON CONFLICT.
-- ---------------------------------------------------------------------
INSERT INTO PlataformaUsuario (nro_plataforma, nick_usuario, nro_usuario)
SELECT (1 + floor(random() * 1000))::int,
       'user' || (1 + floor(random() * 5000))::int,
       (1 + floor(random() * 999999))::int
FROM generate_series(1, 6300) AS i
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------
-- 7) StreamerPais (~1500) -- pool de "streamers" = user1..user1500
--    (convenção usada também em Canal e Participa mais abaixo)
-- ---------------------------------------------------------------------
INSERT INTO StreamerPais (nick_streamer, ddi_pais, nro_passaporte)
SELECT 'user' || (1 + floor(random() * 1500))::int,
       (1 + floor(random() * 1000))::int,
       'PSP' || lpad((floor(random() * 99999999))::text, 8, '0')
FROM generate_series(1, 1600) AS i
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------
-- 8) EmpresaPais (~1200)
-- ---------------------------------------------------------------------
INSERT INTO EmpresaPais (nro_empresa, ddi_pais, id_nacional)
SELECT (1 + floor(random() * 1200))::bigint,
       (1 + floor(random() * 1000))::int,
       'CNPJ' || lpad((floor(random() * 99999999999999))::text, 14, '0')
FROM generate_series(1, 1260) AS i
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------
-- 9) Canal (1800) -- nome sintético 'Canal_i' garante UNIQUE(nome,plataforma)
--    sem depender de colisão. Dono sempre do pool de streamers (user1..1500).
-- ---------------------------------------------------------------------
INSERT INTO Canal (nome, nro_plataforma, tipo, data, descricao, nick_streamer)
SELECT 'Canal_' || i,
       (1 + floor(random() * 1000))::int,
       (ARRAY['privado', 'publico', 'misto'])[1 + floor(random() * 3)],
       CURRENT_DATE - (floor(random() * 3650))::int,
       'Canal gerado automaticamente para fins de teste (#' || i || ')',
       'user' || (1 + floor(random() * 1500))::int
FROM generate_series(1, 1800) AS i;

-- ---------------------------------------------------------------------
-- 10) NivelCanal (9000 = 5 por canal, respeitando "existem cinco níveis")
--     Gerado de forma totalmente determinística -> nunca colide.
-- ---------------------------------------------------------------------
INSERT INTO NivelCanal (id_canal, nivel, valor, gif)
SELECT c.id_canal, n.nivel,
       round((5 + n.nivel * 5 + random() * 10)::numeric, 2),
       'nivel_' || n.nivel || '.gif'
FROM generate_series(1, 1800) AS c(id_canal)
CROSS JOIN generate_series(1, 5) AS n(nivel)
ORDER BY c.id_canal, n.nivel;

-- ---------------------------------------------------------------------
-- 11) Patrocinio (~1800)
-- ---------------------------------------------------------------------
INSERT INTO Patrocinio (nro_empresa, id_canal, valor)
SELECT (1 + floor(random() * 1200))::bigint,
       (1 + floor(random() * 1800))::bigint,
       round((500 + random() * 49500)::numeric, 2)
FROM generate_series(1, 1900) AS i
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------
-- 12) Inscricao (~7000) -- id_canal e id_nivel_canal vêm do MESMO
--     registro de NivelCanal (via LATERAL) para manter consistência
--     lógica entre as duas FKs, já que não há FK composta cobrindo isso.
-- ---------------------------------------------------------------------
INSERT INTO Inscricao (nick_membro, id_canal, id_nivel_canal)
SELECT 'user' || (1 + floor(random() * 5000))::int,
       nc.id_canal,
       nc.id_nivel_canal
FROM generate_series(1, 7400) AS i
CROSS JOIN LATERAL (
    SELECT id_canal, id_nivel_canal
    FROM NivelCanal
    OFFSET floor(random() * 9000) LIMIT 1
) nc
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------
-- 13) Video (5000) -- titulo sintético garante UNIQUE(id_canal,titulo,dataH)
-- ---------------------------------------------------------------------
INSERT INTO Video (id_canal, titulo, dataH, tema, duracao, visu_simul, visu_total)
SELECT (1 + floor(random() * 1800))::bigint,
       'Video_' || i,
       CURRENT_TIMESTAMP - (random() * 1095 || ' days')::interval,
       (ARRAY['FPS', 'MOBA', 'RPG', 'Battle Royale', 'Estrategia', 'Corrida',
              'Esportes', 'Puzzle', 'Terror', 'Simulação', 'Sandbox', 'Luta']
       )[1 + floor(random() * 12)],
       make_interval(mins => (5 + floor(random() * 175))::int),
       (floor(random() * 50000))::int,
       (floor(random() * 2000000))::bigint
FROM generate_series(1, 5000) AS i;

-- ---------------------------------------------------------------------
-- 14) Participa (~3000) -- streamers convidados, do pool user1..1500
-- ---------------------------------------------------------------------
INSERT INTO Participa (id_video, nick_streamer)
SELECT (1 + floor(random() * 5000))::bigint,
       'user' || (1 + floor(random() * 1500))::int
FROM generate_series(1, 3150) AS i
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------
-- 15) Comentario (9000) -- seq calculado via ROW_NUMBER() particionado
--     por (id_video, nick_usuario): garante UNIQUE por construção, sem
--     nenhuma chance de colisão e sem precisar de ON CONFLICT.
-- ---------------------------------------------------------------------
INSERT INTO Comentario (id_video, nick_usuario, seq, texto, dataH, coment_on)
SELECT id_video, nick_usuario,
       ROW_NUMBER() OVER (PARTITION BY id_video, nick_usuario ORDER BY ordem) AS seq,
       texto, dataH, coment_on
FROM (
    SELECT
        (1 + floor(random() * 5000))::bigint AS id_video,
        'user' || (1 + floor(random() * 5000))::int AS nick_usuario,
        'Comentário automático de teste #' || i AS texto,
        CURRENT_TIMESTAMP - (random() * 1095 || ' days')::interval AS dataH,
        (random() < 0.8) AS coment_on,
        random() AS ordem
    FROM generate_series(1, 9000) AS i
) AS sub;

-- ---------------------------------------------------------------------
-- 16) Doacao (4800) -- seq_pg calculado via ROW_NUMBER() particionado
--     por id_comentario: mesma técnica do item 15.
-- ---------------------------------------------------------------------
INSERT INTO Doacao (id_comentario, seq_pg, valor, status)
SELECT id_comentario,
       ROW_NUMBER() OVER (PARTITION BY id_comentario ORDER BY ordem) AS seq_pg,
       valor, status
FROM (
    SELECT
        (1 + floor(random() * 9000))::bigint AS id_comentario,
        round((1 + random() * 499)::numeric, 2) AS valor,
        (ARRAY['recusado', 'recebido', 'lido'])[1 + floor(random() * 3)] AS status,
        random() AS ordem
    FROM generate_series(1, 4800) AS i
) AS sub;

-- ---------------------------------------------------------------------
-- 17-20) Subtabelas de forma de pagamento (~1200 cada)
--        Divisão determinística por id_doacao % 4 -- cada doação cai em
--        exatamente UMA das 4 tabelas (a trigger de exclusividade que
--        faremos depois passa a VALIDAR essa regra; aqui ela já nasce
--        respeitada por construção).
-- ---------------------------------------------------------------------
INSERT INTO BitCoin (id_doacao, TxID)
SELECT id_doacao, 'TX' || lpad(id_doacao::text, 10, '0') || md5(random()::text)
FROM Doacao WHERE id_doacao % 4 = 0;

INSERT INTO PayPal (id_doacao, IdPayPal)
SELECT id_doacao, 'PP-' || lpad(id_doacao::text, 10, '0')
FROM Doacao WHERE id_doacao % 4 = 1;

INSERT INTO CartaoCredito (id_doacao, nro, bandeira)
SELECT id_doacao,
       lpad((floor(random() * 9999999999999999))::text, 16, '0'),
       (ARRAY['Visa', 'Mastercard', 'Elo', 'American Express', 'Hipercard'])[1 + floor(random() * 5)]
FROM Doacao WHERE id_doacao % 4 = 2;

INSERT INTO MecanismoPlat (id_doacao, seq_plataforma)
SELECT id_doacao, (1 + floor(random() * 1000))::int
FROM Doacao WHERE id_doacao % 4 = 3;

-- =====================================================================
-- Conferência de volumetria: rode check_volumetria.sql depois deste
-- script para confirmar que todas as tabelas ficaram entre 1.000 e
-- 10.000 tuplas.
-- =====================================================================
