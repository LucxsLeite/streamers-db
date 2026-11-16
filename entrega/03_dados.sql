BEGIN;

-- ============================================================
-- 1. Tabelas de base (domínio pequeno, declarado no relatório)
-- ============================================================
INSERT INTO Conversao (moeda, nome, fator_conver) VALUES
    ('BRL', 'Real', 0.19), ('USD', 'Dólar', 1.00), ('EUR', 'Euro', 1.08),
    ('GBP', 'Libra', 1.27), ('JPY', 'Iene', 0.0067), ('MXN', 'Peso mexicano', 0.055);

INSERT INTO Pais (ddi, nome, moeda) VALUES
    (55, 'Brasil', 'BRL'), (1, 'Estados Unidos', 'USD'), (351, 'Portugal', 'EUR'),
    (44, 'Reino Unido', 'GBP'), (81, 'Japão', 'JPY'), (52, 'México', 'MXN'),
    (49, 'Alemanha', 'EUR'), (33, 'França', 'EUR');

INSERT INTO Empresa (nro, nome, nome_fantasia)
SELECT k, 'Empresa ' || k, 'EF' || k FROM generate_series(1, 1000) k;

INSERT INTO Plataforma (nro, nome, data_fund, empresa_fund, empresa_respo) VALUES
    (1, 'YouTube', '2005-02-14', 1, 2),
    (2, 'Twitch',  '2011-06-06', 3, 4),
    (3, 'Kick',    '2022-12-01', 5, 6);

INSERT INTO EmpresaPais (nro_empresa, ddi_pais, id_nacional)
SELECT k, (ARRAY[55,1,351,44,81,52,49,33])[1 + floor(random()*8)::int], 'NAC' || lpad(k::text, 6, '0')
  FROM generate_series(1, 1000) k;

-- ============================================================
-- 2. Usuários (5.000) e plataformas
-- ============================================================
INSERT INTO Usuario (nick, email, data_nasc, telefone, end_postal, pais_residencia)
SELECT nick,
       nick || '@mail.com',
       DATE '1960-01-01' + floor(random()*16000)::int,
       '+55 21 9' || lpad(k::text, 8, '0'),
       'Rua ' || k || ', ' || k,
       (ARRAY[55,1,351,44,81,52,49,33])[1 + floor(random()*8)::int]
FROM (
    SELECT k, (ARRAY['gamer','ana','lucas','bia','pedro','mari','joao','leo','zeca','kaka'])[1 + mod(k,10)]
              || '_' || k AS nick
      FROM generate_series(1, 5000) k
) x;

CREATE TEMP TABLE u_idx AS
SELECT (row_number() OVER (ORDER BY nick))::int AS i, nick FROM Usuario;

INSERT INTO PlataformaUsuario (nro_plataforma, nick_usuario, nro_usuario)
SELECT 1 + mod(i,3), nick, i FROM u_idx;

-- ============================================================
-- 3. Streamers (300) com passaporte
-- ============================================================
CREATE TEMP TABLE st AS
SELECT i, nick FROM u_idx WHERE i <= 300;

INSERT INTO StreamerPais (nick_streamer, ddi_pais, nro_passaporte)
SELECT s.nick, (ARRAY[55,1,351,44,81,52,49,33])[1 + mod(s.i,8)],
       'PASS' || lpad(s.i::text, 6, '0')
  FROM st s;

INSERT INTO StreamerPais (nick_streamer, ddi_pais, nro_passaporte)
SELECT s.nick, (ARRAY[55,1,351,44,81,52,49,33])[1 + mod(s.i + 3, 8)],
       'PASS2' || lpad(s.i::text, 6, '0')
  FROM st s WHERE mod(s.i,5) = 0
ON CONFLICT DO NOTHING;

-- ============================================================
-- 4. Canais (1.000). Dono sempre é streamer com passaporte.
-- ============================================================
INSERT INTO Canal (nome, nro_plataforma, tipo, data_inicio, descricao, nick_streamer)
SELECT (ARRAY['GamerTV','Pro Arena','Bia Canta','Lucas Games','Pixel Lab','Terra Jogos'])[1 + mod(k,6)]
       || ' ' || k,
       1 + mod(k,3),
       CASE WHEN random() < 0.8 THEN 'público' WHEN random() < 0.5 THEN 'misto' ELSE 'privado' END,
       DATE '2019-01-01' + floor(random()*2500)::int,
       'Canal de ' || (ARRAY['games','música','culinária','tecnologia'])[1 + mod(k,4)],
       s.nick
  FROM generate_series(1, 1000) k
  JOIN st s ON s.i = 1 + mod(k, 300);

-- 5 níveis por canal (trigger T05 confere no COMMIT)
INSERT INTO NivelCanal (id_canal, nivel, valor, gif)
SELECT c.id_canal, n.nivel,
       round((n.valor * (0.8 + random()*0.4))::numeric, 2),
       'nivel_' || c.id_canal || '_' || lower(n.nivel) || '.gif'
  FROM Canal c
 CROSS JOIN (VALUES ('Bronze', 3), ('Prata', 5), ('Ouro', 10), ('Diamante', 20), ('Lenda', 50))
       AS n(nivel, valor);

-- patrocínios: poucos canais recebem muitos (cauda longa)
INSERT INTO Patrocinio (nro_empresa, id_canal, valor)
SELECT (1 + floor(random()*1000))::int, c.id_canal,
       round((100 + power(random(),2)*5000)::numeric, 2)
  FROM Canal c
 CROSS JOIN LATERAL generate_series(1, floor(power(random(),2)*5)::int) g
ON CONFLICT DO NOTHING;

-- membros: canais grandes têm mais membros.
-- Exclui o dono do canal (trigger T09) e usa o nível do canal.
WITH gen AS MATERIALIZED (
    SELECT c.id_canal,
           (1 + floor(random()*5000))::int AS ui,
           (1 + floor(random()*5))::int AS ni
      FROM Canal c
     CROSS JOIN LATERAL generate_series(1, floor(power(random(),2)*8)::int) g
)
INSERT INTO Inscricao (id_canal, nick_membro, nivel)
SELECT g.id_canal, u.nick,
       (ARRAY['Bronze','Prata','Ouro','Diamante','Lenda'])[g.ni]
  FROM gen g
  JOIN u_idx u ON u.i = g.ui
  JOIN Canal c ON c.id_canal = g.id_canal
 WHERE u.nick <> c.nick_streamer
ON CONFLICT DO NOTHING;

-- ============================================================
-- 5. Vídeos (cauda longa). Data sempre >= início do canal (T07).
-- ============================================================
CREATE TEMP TABLE pesos AS
SELECT id_canal, nome, data_inicio, power(random(), 3) AS p FROM Canal;

INSERT INTO Video (id_canal, titulo, dataH, tema, duracao, visu_simul, visu_total)
SELECT g.id_canal,
       'Episódio ' || g.k || ' - ' || g.nome,
       g.data_v,
       (ARRAY['RPG','Speedrun','Just Chatting','FPS','Estratégia','Terror'])[1 + floor(random()*6)::int],
       (5 + floor(random()*240))::int * INTERVAL '1 minute',
       floor(g.vt * (0.01 + random()*0.15))::int,
       g.vt
  FROM (
      SELECT p.id_canal, p.nome, k,
             p.data_inicio::timestamp
                 + floor(random()*1000)::int * INTERVAL '1 day'
                 + floor(random()*24)::int * INTERVAL '1 hour' AS data_v,
             floor(power(random(),2) * 400000 * (0.1 + p.p))::int AS vt
        FROM pesos p
       CROSS JOIN LATERAL generate_series(1, 1 + floor(p.p*25)::int) k
  ) g;

-- ============================================================
-- 6. Comentários (seq de 1..N por vídeo, após a postagem: T10)
-- ============================================================
WITH gen AS MATERIALIZED (
    SELECT v.id_video, v.dataH AS data_v, k,
           (1 + floor(random()*5000))::int AS ui,
           random() AS r
      FROM Video v
     CROSS JOIN LATERAL generate_series(1, floor(power(random(),2)*5)::int) k
)
INSERT INTO Comentario (id_video, seq, nick_usuario, texto, dataH, coment_on)
SELECT g.id_video, g.k, u.nick,
       (ARRAY['Boa!','Que lenda','Começou!','Kkkkk','Melhor episódio',
              'Não acredito','Manda outro','Muito bom'])[1 + floor(g.r*8)::int],
       g.data_v + g.k * INTERVAL '2 minutes' + floor(g.r*3600) * INTERVAL '1 second',
       g.r < 0.6
  FROM gen g
  JOIN u_idx u ON u.i = g.ui;

-- participação de streamers convidados (~15% dos vídeos).
-- Exclui o dono do canal do vídeo (trigger T08).
WITH v AS MATERIALIZED (
    SELECT vid.id_video, vid.id_canal, (1 + floor(random()*300))::int AS si
      FROM Video vid WHERE random() < 0.15
)
INSERT INTO Participa (id_video, nick_streamer)
SELECT v.id_video, s.nick
  FROM v
  JOIN st s ON s.i = v.si
  JOIN Canal c ON c.id_canal = v.id_canal
 WHERE s.nick <> c.nick_streamer
ON CONFLICT DO NOTHING;

-- ============================================================
-- 7. Doações (~50% dos comentários). Trigger T06 converte para USD.
-- ============================================================
WITH cand AS MATERIALIZED (
    SELECT c.id_comentario, c.nick_usuario
      FROM Comentario c
     WHERE random() < 0.5
)
INSERT INTO Doacao (id_comentario, moeda, valor_original, status)
SELECT c.id_comentario, p.moeda,
       round((5 + power(random(),2)*300)::numeric, 2),
       CASE WHEN random() < 0.7 THEN 'recebido'
            WHEN random() < 0.5 THEN 'lido'
            ELSE 'recusado' END
  FROM cand c
  JOIN Usuario u ON u.nick = c.nick_usuario
  JOIN Pais p    ON p.ddi = u.pais_residencia;

CREATE TEMP TABLE tmp_meio AS
SELECT id_comentario, (id_comentario % 4) AS m FROM Doacao;

INSERT INTO Cartao (nro, bandeira)
SELECT 'CARD' || lpad(k::text, 6, '0'),
       (ARRAY['Visa','Mastercard','Elo','Amex'])[1 + floor(random()*4)::int]
  FROM generate_series(1, 1000) k;

INSERT INTO CartaoCredito (id_comentario, nro_cartao)
SELECT id_comentario, 'CARD' || lpad((1 + mod(id_comentario, 1000))::text, 6, '0')
  FROM tmp_meio WHERE m = 0;

INSERT INTO BitCoin (id_comentario, TxID)
SELECT id_comentario, 'tx' || md5(id_comentario::text || random()::text)
  FROM tmp_meio WHERE m = 1;

INSERT INTO PayPal (id_comentario, IdPayPal)
SELECT id_comentario, 'PP' || lpad(id_comentario::text, 8, '0')
  FROM tmp_meio WHERE m = 2;

INSERT INTO MecanismoPlat (id_comentario, seq_plataforma)
SELECT id_comentario, id_comentario * 7 + 1000
  FROM tmp_meio WHERE m = 3;

-- ============================================================
-- 8. Bloco de referência fixa (nomes conhecidos para os testes)
-- ============================================================
INSERT INTO Usuario (nick, email, data_nasc, telefone, end_postal, pais_residencia) VALUES
    ('ana_fan',  'ana@ref.com',   '2000-01-01', '+55 21 900000001', 'Rua Ref A', 55),
    ('pedro_gg', 'pedro@ref.com', '1999-01-01', '+55 21 900000002', 'Rua Ref B', 55);

INSERT INTO StreamerPais (nick_streamer, ddi_pais, nro_passaporte)
    VALUES ('ana_fan', 55, 'REF0001');

INSERT INTO Canal (nome, nro_plataforma, tipo, data_inicio, nick_streamer)
    VALUES ('GamerTV', 1, 'público', '2020-01-01', 'ana_fan');

INSERT INTO NivelCanal (id_canal, nivel, valor, gif)
SELECT c.id_canal, n.nivel, n.valor, 'ref_' || n.nivel || '.gif'
  FROM Canal c
 CROSS JOIN (VALUES ('Bronze', 3.00), ('Prata', 5.00), ('Ouro', 10.00),
                    ('Diamante', 20.00), ('Lenda', 50.00)) AS n(nivel, valor)
 WHERE c.nome = 'GamerTV';

INSERT INTO Video (id_canal, titulo, dataH, tema, duracao, visu_simul, visu_total)
SELECT id_canal, 'Zerando', '2026-03-10 19:00', 'RPG', INTERVAL '1 hour', 100, 500
  FROM Canal WHERE nome = 'GamerTV';

INSERT INTO Comentario (id_video, seq, nick_usuario, texto, dataH, coment_on)
SELECT id_video, 1, 'pedro_gg', 'Boa', '2026-03-10 19:02', TRUE
  FROM Video WHERE titulo = 'Zerando';

INSERT INTO Doacao (id_comentario, moeda, valor_original, status)
SELECT c.id_comentario, 'BRL', 100.00, 'recebido'
  FROM Comentario c JOIN Video v ON v.id_video = c.id_video
 WHERE v.titulo = 'Zerando' AND c.seq = 1;
 
INSERT INTO CartaoCredito (id_comentario, nro_cartao)
SELECT c.id_comentario, 'CARD000001'
  FROM Comentario c JOIN Video v ON v.id_video = c.id_video
 WHERE v.titulo = 'Zerando' AND c.seq = 1;

COMMIT;

-- Atualiza as visões materializadas (criadas vazias no 02_plsql.sql)
CALL sp_atualizar_visoes();
