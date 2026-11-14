-- =====================================================================
-- PROJETO DE BANCO DE DADOS 2026/2 - UFF - Prof. Marcos Bedo
-- Arquivo 3: carga de dados artificiais
--
-- * Tudo roda em UMA transação: as regras "verificadas no COMMIT"
--   (T9a, T9b, T12, T15) só podem ser conferidas no fim.
-- * Os triggers ficam LIGADOS durante a carga e preenchem sozinhos:
--   plataforma.qtd_users (T1), canal.qtd_videos/qtd_visualizacoes (T2),
--   nivel_canal (T3), comentario.seq (T7), doacao.seq_pg (T8),
--   doacao.moeda/valor_usd (T16) e mecanismo_plat.seq_plataforma (T8b).
-- * Volumes (todos entre 1.000 e 10.000 linhas):
--   conversao 1000 | pais 1000 | empresa 2000 | empresa_pais 2500
--   plataforma 1000 | usuario 10000 | plataforma_usuario 10000
--   streamer_pais 1300 | canal 2000 | patrocinio 1900
--   nivel_canal 10000 (T3) | inscricao 10000 | video 10000
--   participa ~10000 | comentario 10000 | doacao 8000
--   bitcoin/paypal/cartao_credito/mecanismo_plat ~2000 cada
-- =====================================================================

SELECT setseed(0.42);   -- dados reproduzíveis

BEGIN;

-- ---------- moedas e países (códigos de moeda artificiais de 3 letras) ----------
INSERT INTO conversao (moeda, nome, fator_conver)
SELECT chr(65 + (i / 676) % 26) || chr(65 + (i / 26) % 26) || chr(65 + i % 26),
       'Moeda ' || (i + 1),
       ROUND((0.01 + random() * 4.99)::numeric, 6)
  FROM generate_series(0, 999) AS i;

INSERT INTO pais (ddi, nome, moeda)
SELECT i + 1,
       'Pais ' || (i + 1),
       chr(65 + (i / 676) % 26) || chr(65 + (i / 26) % 26) || chr(65 + i % 26)
  FROM generate_series(0, 999) AS i;

-- ---------- empresas (T9b: cada uma com ao menos um país, na mesma transação) ----------
INSERT INTO empresa (id_empresa, nome, nome_fantasia)
SELECT e, 'Empresa ' || e, 'Fantasia ' || e
  FROM generate_series(1, 2000) AS e;

INSERT INTO empresa_pais (id_empresa, ddi, id_nacional)
SELECT e, (e % 1000) + 1, 'CN' || lpad(e::text, 8, '0')
  FROM generate_series(1, 2000) AS e
UNION ALL
SELECT e, ((e + 500) % 1000) + 1, 'CN2' || lpad(e::text, 8, '0')
  FROM generate_series(1, 500) AS e;

-- ---------- plataformas (qtd_users nasce 0 e é mantido por T1) ----------
INSERT INTO plataforma (nro_plataforma, nome, empresa_fund, empresa_respo, data_fund)
SELECT p,
       'Plataforma ' || p,
       1 + ((p * 7) % 2000),
       1 + ((p * 11) % 2000),
       DATE '2000-01-01' + floor(random() * 8000)::int
  FROM generate_series(1, 1000) AS p;

-- ---------- usuários e contas nas plataformas ----------
INSERT INTO usuario (nick, email, data_nasc, telefone, end_postal, pais_residencia)
SELECT 'user_' || i,
       'user_' || i || '@exemplo.com',
       DATE '1960-01-01' + floor(random() * 14000)::int,
       '+55119' || lpad(i::text, 8, '0'),
       'Rua ' || i || ', Cidade ' || (i % 500),
       1 + floor(random() * 1000)::int
  FROM generate_series(1, 10000) AS i;

INSERT INTO plataforma_usuario (nro_plataforma, nick_usuario, nro_usuario)
SELECT 1 + floor(1000 * power(random(), 2))::int,      -- plataformas de id baixo são mais populares
       'user_' || i,
       100000 + i
  FROM generate_series(1, 10000) AS i;

-- ---------- streamers: user_1..user_1000, com 1 passaporte (300 com 2) ----------
INSERT INTO streamer_pais (nick_streamer, ddi_pais, nro_passaporte)
SELECT 'user_' || i, (i % 1000) + 1, 'P1' || lpad(i::text, 8, '0')
  FROM generate_series(1, 1000) AS i
UNION ALL
SELECT 'user_' || i, ((i + 333) % 1000) + 1, 'P2' || lpad(i::text, 8, '0')
  FROM generate_series(1, 300) AS i;

-- ---------- canais (T3 cria os 5 níveis; T15 exige 1 canal por streamer) ----------
-- canais 1..1000: um para cada streamer; 1001..2000: dono sorteado entre os streamers
INSERT INTO canal (id_canal, nome, nro_plataforma, nick_streamer, tipo, data_inicio, descricao)
WITH b AS (
    SELECT g,
           1 + floor(1000 * power(random(), 2))::int                              AS plat,
           CASE WHEN g <= 1000 THEN g
                ELSE 1 + floor(1000 * power(random(), 2))::int END                AS dono,
           1 + floor(random() * 3)::int                                           AS t,
           DATE '2015-01-01' + floor(random() * 2900)::int                        AS ini
      FROM generate_series(1, 2000) AS g
)
SELECT g,
       'canal_' || g,
       plat,
       'user_' || dono,
       (ARRAY['privado', 'publico', 'misto'])[t],
       ini,
       'Canal de jogos número ' || g
  FROM b;

-- ---------- patrocínios vigentes (1900 canais, 1 empresa cada) ----------
INSERT INTO patrocinio (id_empresa, id_canal, valor)
SELECT 1 + floor(random() * 2000)::int,
       c,
       ROUND((100 + random() * 49900)::numeric, 2)
  FROM generate_series(1, 1900) AS c;

-- ---------- membros vigentes: usuários 1001..5000 (nunca donos), 2 ou 3 canais cada ----------
INSERT INTO inscricao (nick_membro, id_canal, nivel)
SELECT 'user_' || u,
       ((u * 13 + k * 667) % 2000) + 1,
       1 + ((u + k) % 5)
  FROM (SELECT 1000 + ((i - 1) % 4000) + 1 AS u,
               (i - 1) / 4000              AS k
          FROM generate_series(1, 10000) AS i) AS t;

-- ---------- vídeos (T4: sempre depois do início do canal; T2 atualiza o canal) ----------
INSERT INTO video (id_video, id_canal, titulo, data_hora, tema, duracao, visu_simul, visu_total)
WITH b AS (
    SELECT g,
           1 + floor(2000 * power(random(), 2))::int       AS cid,
           (100 + floor(random() * 500000))::int            AS vt,
           1 + floor(random() * 6)::int                     AS t,
           1 + floor(random() * 1200)::int                  AS dias,
           floor(random() * 86400)::int                     AS seg,
           10 + floor(random() * 230)::int                  AS minutos,
           (0.01 + random() * 0.2)                          AS fr
      FROM generate_series(1, 10000) AS g
)
SELECT b.g,
       b.cid,
       'Video ' || b.g,
       c.data_inicio::timestamp + b.dias * INTERVAL '1 day' + b.seg * INTERVAL '1 second',
       (ARRAY['FPS', 'RPG', 'Estratégia', 'Corrida', 'Esportes', 'Aventura'])[b.t],
       make_interval(mins => b.minutos),
       (b.vt * b.fr)::int,
       b.vt
  FROM b
  JOIN canal c ON c.id_canal = b.cid;

-- ---------- convidados: 2 por vídeo nos vídeos 1..5000 (nunca o dono: T5) ----------
INSERT INTO participa (id_video, nick_streamer)
SELECT g.v, 'user_' || g.s
  FROM (SELECT v, 1 + ((v * 17) % 1000) AS s FROM generate_series(1, 5000) AS v
        UNION ALL
        SELECT v, 1 + ((v * 29 + 5) % 1000) AS s FROM generate_series(1, 5000) AS v) AS g
  JOIN video vi ON vi.id_video = g.v
  JOIN canal c  ON c.id_canal  = vi.id_canal
 WHERE c.nick_streamer <> 'user_' || g.s;

-- ---------- comentários (seq por T7; data >= postagem do vídeo) ----------
INSERT INTO comentario (id_video, nick_usuario, texto, data_hora, coment_on)
WITH b AS (
    SELECT j,
           1 + floor(10000 * power(random(), 2))::int AS vid,
           1 + floor(random() * 10000)::int           AS u,
           (random() < 0.7)                           AS online,
           floor(random() * 300)::int                 AS horas,
           floor(random() * 3600)::int                AS seg
      FROM generate_series(1, 10000) AS j
)
SELECT b.vid,
       'user_' || b.u,
       'Comentário ' || b.j,
       v.data_hora + b.horas * INTERVAL '1 hour' + b.seg * INTERVAL '1 second',
       b.online
  FROM b
  JOIN video v ON v.id_video = b.vid
 ORDER BY b.j;

-- ---------- doações: 8000 (valor_original em moeda local; T8 numera, T16 converte p/ USD) ----------
INSERT INTO doacao (id_video, seq_comentario, valor_original, status)
SELECT t.id_video,
       t.seq,
       ROUND((1 + random() * 499)::numeric, 2),
       CASE WHEN random() < 0.10  THEN 'recusado'
            WHEN random() < 0.667 THEN 'recebido'
            ELSE 'lido' END
  FROM (SELECT id_video, seq, ROW_NUMBER() OVER (ORDER BY id_video, seq) AS rn
          FROM comentario) AS t
 CROSS JOIN LATERAL generate_series(1, CASE WHEN t.rn % 5 = 0 THEN 2
                                            WHEN t.rn % 2 = 0 THEN 1
                                            ELSE 0 END) AS n
 ORDER BY t.rn, n;

-- ---------- formas de pagamento (T13/T9a: exatamente uma por doação) ----------
INSERT INTO bitcoin (id_video, seq_comentario, seq_pg, txid)
SELECT id_video, seq_comentario, seq_pg,
       md5('btc-' || id_video || '-' || seq_comentario || '-' || seq_pg)
    || md5('BTC-' || seq_pg || '-' || seq_comentario || '-' || id_video)
  FROM doacao
 WHERE (id_video + seq_comentario + seq_pg) % 4 = 0;

INSERT INTO paypal (id_video, seq_comentario, seq_pg, id_paypal)
SELECT id_video, seq_comentario, seq_pg,
       'PP-' || upper(md5('pp-' || id_video || '-' || seq_comentario || '-' || seq_pg))
  FROM doacao
 WHERE (id_video + seq_comentario + seq_pg) % 4 = 1;

INSERT INTO cartao_credito (id_video, seq_comentario, seq_pg, nro_cartao, bandeira, data_hora)
SELECT d.id_video, d.seq_comentario, d.seq_pg,
       '4' || lpad((ROW_NUMBER() OVER (ORDER BY d.id_video, d.seq_comentario, d.seq_pg))::text, 15, '0'),
       (ARRAY['Visa', 'Mastercard', 'Elo', 'American Express'])[1 + ((d.id_video + d.seq_pg) % 4)],
       c.data_hora
  FROM doacao d
  JOIN comentario c ON c.id_video = d.id_video AND c.seq = d.seq_comentario
 WHERE (d.id_video + d.seq_comentario + d.seq_pg) % 4 = 2;

INSERT INTO mecanismo_plat (id_video, seq_comentario, seq_pg)
SELECT id_video, seq_comentario, seq_pg
  FROM doacao
 WHERE (id_video + seq_comentario + seq_pg) % 4 = 3
 ORDER BY id_video, seq_comentario, seq_pg;

COMMIT;   -- aqui rodam T9a, T9b, T12 e T15

-- ---------- pós-carga ----------
-- Alinha as sequences dos identificadores artificiais com os ids carregados
SELECT setval(pg_get_serial_sequence('empresa',    'id_empresa'),     (SELECT MAX(id_empresa)     FROM empresa));
SELECT setval(pg_get_serial_sequence('plataforma', 'nro_plataforma'), (SELECT MAX(nro_plataforma) FROM plataforma));
SELECT setval(pg_get_serial_sequence('canal',      'id_canal'),       (SELECT MAX(id_canal)       FROM canal));
SELECT setval(pg_get_serial_sequence('video',      'id_video'),       (SELECT MAX(id_video)       FROM video));

ANALYZE;
CALL sp_atualizar_visoes();

-- Conferência dos volumes
SELECT 'conversao' AS tabela, COUNT(*) AS linhas FROM conversao
UNION ALL SELECT 'pais',               COUNT(*) FROM pais
UNION ALL SELECT 'empresa',            COUNT(*) FROM empresa
UNION ALL SELECT 'empresa_pais',       COUNT(*) FROM empresa_pais
UNION ALL SELECT 'plataforma',         COUNT(*) FROM plataforma
UNION ALL SELECT 'usuario',            COUNT(*) FROM usuario
UNION ALL SELECT 'plataforma_usuario', COUNT(*) FROM plataforma_usuario
UNION ALL SELECT 'streamer_pais',      COUNT(*) FROM streamer_pais
UNION ALL SELECT 'canal',              COUNT(*) FROM canal
UNION ALL SELECT 'patrocinio',         COUNT(*) FROM patrocinio
UNION ALL SELECT 'nivel_canal',        COUNT(*) FROM nivel_canal
UNION ALL SELECT 'inscricao',          COUNT(*) FROM inscricao
UNION ALL SELECT 'video',              COUNT(*) FROM video
UNION ALL SELECT 'participa',          COUNT(*) FROM participa
UNION ALL SELECT 'comentario',         COUNT(*) FROM comentario
UNION ALL SELECT 'doacao',             COUNT(*) FROM doacao
UNION ALL SELECT 'bitcoin',            COUNT(*) FROM bitcoin
UNION ALL SELECT 'paypal',             COUNT(*) FROM paypal
UNION ALL SELECT 'cartao_credito',     COUNT(*) FROM cartao_credito
UNION ALL SELECT 'mecanismo_plat',     COUNT(*) FROM mecanismo_plat;
