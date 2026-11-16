-- ---------------------------------------------------------------------
-- Blocos de falha usam ROLLBACK para deixar a sessão limpa.
-- Parte 1: triggers. Parte 2: functions de consulta (somente leitura).
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- T01: passaporte para dono de canal
-- ---------------------------------------------------------------------
-- PASSA: ana_fan tem passaporte
INSERT INTO Canal (nome, nro_plataforma, tipo, data_inicio, nick_streamer)
VALUES ('CanalT01Ok', 1, 'público', '2020-01-01', 'ana_fan');
-- FALHA "T01:": pedro_gg não tem passaporte
INSERT INTO Canal (nome, nro_plataforma, tipo, data_inicio, nick_streamer)
VALUES ('CanalT01Erro', 1, 'público', '2020-01-01', 'pedro_gg');


-- ---------------------------------------------------------------------
-- T02: não apagar o último passaporte de quem tem canal
-- ---------------------------------------------------------------------
-- PASSA: ana_fan ganha passaporte de Portugal; remover o do Brasil é permitido
INSERT INTO StreamerPais (nick_streamer, ddi_pais, nro_passaporte)
VALUES ('ana_fan', 351, 'PT_REF');
DELETE FROM StreamerPais WHERE nick_streamer = 'ana_fan' AND ddi_pais = 55;
-- FALHA "T02:": é o último passaporte de ana_fan, que tem canal
DELETE FROM StreamerPais WHERE nick_streamer = 'ana_fan' AND ddi_pais = 351;


-- ---------------------------------------------------------------------
-- T03: doação em no máximo um meio de pagamento
-- ---------------------------------------------------------------------
-- PASSA: comentário novo, doação e um meio (tudo no mesmo bloco, por causa de T04)
BEGIN;
INSERT INTO Comentario (id_video, seq, nick_usuario, texto, dataH, coment_on)
SELECT id_video, 22, 'pedro_gg', 'T03 ok', '2026-03-10 21:00', TRUE
  FROM Video WHERE titulo = 'Zerando';
INSERT INTO Doacao (id_comentario, moeda, valor_original, status)
SELECT c.id_comentario, 'BRL', 10.00, 'recebido'
  FROM Comentario c JOIN Video v ON v.id_video = c.id_video
 WHERE v.titulo = 'Zerando' AND c.seq = 22;
INSERT INTO CartaoCredito (id_comentario, nro_cartao)
SELECT c.id_comentario, 'CARD000003'
  FROM Comentario c JOIN Video v ON v.id_video = c.id_video
 WHERE v.titulo = 'Zerando' AND c.seq = 22;
COMMIT;
-- FALHA "T03:": segundo meio (PayPal) para a mesma doação
BEGIN;
INSERT INTO Comentario (id_video, seq, nick_usuario, texto, dataH, coment_on)
SELECT id_video, 23, 'pedro_gg', 'T03 erro', '2026-03-10 21:05', TRUE
  FROM Video WHERE titulo = 'Zerando';
INSERT INTO Doacao (id_comentario, moeda, valor_original, status)
SELECT c.id_comentario, 'BRL', 10.00, 'recebido'
  FROM Comentario c JOIN Video v ON v.id_video = c.id_video
 WHERE v.titulo = 'Zerando' AND c.seq = 23;
INSERT INTO CartaoCredito (id_comentario, nro_cartao)
SELECT c.id_comentario, 'CARD000004'
  FROM Comentario c JOIN Video v ON v.id_video = c.id_video
 WHERE v.titulo = 'Zerando' AND c.seq = 23;
INSERT INTO PayPal (id_comentario, IdPayPal)
SELECT c.id_comentario, 'PP-T03-TESTE'
  FROM Comentario c JOIN Video v ON v.id_video = c.id_video
 WHERE v.titulo = 'Zerando' AND c.seq = 23;
COMMIT;
ROLLBACK;


-- ---------------------------------------------------------------------
-- T04: toda doação tem exatamente uma forma de pagamento (no COMMIT)
-- ---------------------------------------------------------------------
-- FALHA "T04:": doação sem nenhum meio de pagamento
BEGIN;
INSERT INTO Comentario (id_video, seq, nick_usuario, texto, dataH, coment_on)
SELECT id_video, 24, 'pedro_gg', 'T04', '2026-03-10 21:10', TRUE
  FROM Video WHERE titulo = 'Zerando';
INSERT INTO Doacao (id_comentario, moeda, valor_original, status)
SELECT c.id_comentario, 'BRL', 10.00, 'recebido'
  FROM Comentario c JOIN Video v ON v.id_video = c.id_video
 WHERE v.titulo = 'Zerando' AND c.seq = 24;
COMMIT;
ROLLBACK;


-- ---------------------------------------------------------------------
-- T05: canal com exatamente cinco níveis (no COMMIT)
-- ---------------------------------------------------------------------
-- PASSA: canal com cinco níveis no mesmo bloco
BEGIN;
INSERT INTO Canal (nome, nro_plataforma, tipo, data_inicio, nick_streamer)
VALUES ('CanalT05Ok', 1, 'público', '2021-01-01', 'ana_fan');
INSERT INTO NivelCanal (id_canal, nivel, valor, gif)
SELECT id_canal, n.nivel, n.valor, 'g' || n.nivel || '.gif'
  FROM Canal c CROSS JOIN (VALUES ('Bronze',3),('Prata',5),('Ouro',10),('Diamante',20),('Lenda',50)) AS n(nivel,valor)
 WHERE c.nome = 'CanalT05Ok';
COMMIT;

-- FALHA "T05:": canal com três níveis
BEGIN;
INSERT INTO Canal (nome, nro_plataforma, tipo, data_inicio, nick_streamer)
VALUES ('CanalT05Erro', 1, 'público', '2021-01-01', 'ana_fan');
INSERT INTO NivelCanal (id_canal, nivel, valor, gif)
SELECT id_canal, n.nivel, n.valor, 'g' || n.nivel || '.gif'
  FROM Canal c CROSS JOIN (VALUES ('Bronze',3),('Prata',5),('Ouro',10)) AS n(nivel,valor)
 WHERE c.nome = 'CanalT05Erro';
COMMIT;
ROLLBACK;


-- ---------------------------------------------------------------------
-- T06: conversão para USD na gravação
-- ---------------------------------------------------------------------
-- PASSA: 100 BRL com fator 0,19 deve gravar valor = 19.00
BEGIN;
INSERT INTO Comentario (id_video, seq, nick_usuario, texto, dataH, coment_on)
SELECT id_video, 20, 'pedro_gg', 'T06 ok', '2026-03-10 21:20', TRUE
  FROM Video WHERE titulo = 'Zerando';
INSERT INTO Doacao (id_comentario, moeda, valor_original, status)
SELECT c.id_comentario, 'BRL', 100.00, 'recebido'
  FROM Comentario c JOIN Video v ON v.id_video = c.id_video
 WHERE v.titulo = 'Zerando' AND c.seq = 20;
INSERT INTO CartaoCredito (id_comentario, nro_cartao)
SELECT c.id_comentario, 'CARD000002'
  FROM Comentario c JOIN Video v ON v.id_video = c.id_video
 WHERE v.titulo = 'Zerando' AND c.seq = 20;
COMMIT;
SELECT d.moeda, d.valor_original, d.valor   -- valor deve ser 19.00
  FROM Doacao d JOIN Comentario c ON c.id_comentario = d.id_comentario
 WHERE c.seq = 20 AND c.id_video = (SELECT id_video FROM Video WHERE titulo = 'Zerando');
-- FALHA "moeda sem fator": XYZ não está em Conversao, então o trigger T06
-- não calcula valor e o NOT NULL recusa a linha (mensagem: valor nulo).
BEGIN;
INSERT INTO Comentario (id_video, seq, nick_usuario, texto, dataH, coment_on)
SELECT id_video, 21, 'pedro_gg', 'T06 erro', '2026-03-10 21:25', TRUE
  FROM Video WHERE titulo = 'Zerando';
INSERT INTO Doacao (id_comentario, moeda, valor_original, status)
SELECT c.id_comentario, 'XYZ', 50.00, 'recebido'
  FROM Comentario c JOIN Video v ON v.id_video = c.id_video
 WHERE v.titulo = 'Zerando' AND c.seq = 21;
COMMIT;
ROLLBACK;


-- ---------------------------------------------------------------------
-- T07: vídeo não anterior ao início do canal
-- ---------------------------------------------------------------------
-- PASSA: vídeo em 2026, canal desde 2020
INSERT INTO Video (id_canal, titulo, dataH, tema, duracao, visu_simul, visu_total)
SELECT id_canal, 'Novo T07', '2026-04-01 10:00', 'RPG', INTERVAL '1 hour', 10, 20
  FROM Canal WHERE nome = 'GamerTV';
-- FALHA "T07:": vídeo de 2019, antes do início do canal
INSERT INTO Video (id_canal, titulo, dataH, tema, duracao, visu_simul, visu_total)
SELECT id_canal, 'Antigo T07', '2019-01-01 10:00', 'RPG', INTERVAL '1 hour', 10, 20
  FROM Canal WHERE nome = 'GamerTV';


-- ---------------------------------------------------------------------
-- T08: dono do canal não é convidado do próprio vídeo
-- ---------------------------------------------------------------------
-- PASSA: convida um streamer com passaporte que não é o dono do canal 'GamerTV'
INSERT INTO Participa (id_video, nick_streamer)
SELECT v.id_video, s.nick_streamer
  FROM Video v
  JOIN Canal c ON c.id_canal = v.id_canal
  JOIN StreamerPais s ON s.nick_streamer <> c.nick_streamer
 WHERE v.titulo = 'Zerando'
 LIMIT 1;
-- FALHA "T08:": dono do canal convidado do próprio vídeo
INSERT INTO Participa (id_video, nick_streamer)
SELECT v.id_video, c.nick_streamer
  FROM Video v
  JOIN Canal c ON c.id_canal = v.id_canal
 WHERE v.titulo = 'Zerando';


-- ---------------------------------------------------------------------
-- T09: dono do canal não é membro dele
-- ---------------------------------------------------------------------
-- PASSA: pedro_gg não é dono do GamerTV
INSERT INTO Inscricao (id_canal, nick_membro, nivel)
SELECT id_canal, 'pedro_gg', 'Bronze' FROM Canal WHERE nome = 'GamerTV';
-- FALHA "T09:": ana_fan é dona do GamerTV
INSERT INTO Inscricao (id_canal, nick_membro, nivel)
SELECT id_canal, 'ana_fan', 'Bronze' FROM Canal WHERE nome = 'GamerTV';


-- ---------------------------------------------------------------------
-- T10: comentário não anterior à postagem do vídeo
-- ---------------------------------------------------------------------
-- PASSA: comentário após a postagem de 'Zerando' (2026-03-10 19:00)
INSERT INTO Comentario (id_video, seq, nick_usuario, texto, dataH, coment_on)
SELECT id_video, 10, 'pedro_gg', 'Teste', '2026-03-10 20:00', TRUE
  FROM Video WHERE titulo = 'Zerando';
-- FALHA "T10:": comentário antes da postagem
INSERT INTO Comentario (id_video, seq, nick_usuario, texto, dataH, coment_on)
SELECT id_video, 11, 'pedro_gg', 'Teste', '2026-03-10 18:00', TRUE
  FROM Video WHERE titulo = 'Zerando';


-- ---------------------------------------------------------------------
-- T11: toda empresa tem ao menos um país de origem (no COMMIT)
-- Usa nro 5000 e 5001: a carga já usa de 1 a 1000.
-- ---------------------------------------------------------------------
-- PASSA: empresa com seu país no mesmo bloco
BEGIN;
INSERT INTO Empresa (nro, nome, nome_fantasia) VALUES (5000, 'Empresa T11', 'ET11');
INSERT INTO EmpresaPais (nro_empresa, ddi_pais, id_nacional) VALUES (5000, 55, 'CNPJ-T11');
COMMIT;

-- FALHA "T11:": empresa sem país de origem
BEGIN;
INSERT INTO Empresa (nro, nome, nome_fantasia) VALUES (5001, 'Empresa Sem Pais', 'ESP');
COMMIT;
ROLLBACK;

-- FALHA "T11:": apagar o único país da empresa 5000
BEGIN;
DELETE FROM EmpresaPais WHERE nro_empresa = 5000;
COMMIT;
ROLLBACK;


-- #####################################################################
-- PARTE 2 - CONSULTAS
-- Atualiza as materializadas (a parte 1 inseriu comentários e doações).
-- #####################################################################

CALL sp_atualizar_visoes();

-- Q1: streamers com mais vídeos (todas, plataforma 1, plataforma inexistente)
SELECT * FROM fn_q01_streamers_mais_videos() LIMIT 10;
SELECT * FROM fn_q01_streamers_mais_videos(1) LIMIT 10;
SELECT * FROM fn_q01_streamers_mais_videos(999);            -- vazio

-- Q2: vídeos mais comentados (todos e de um canal)
SELECT * FROM fn_q02_videos_mais_comentados() LIMIT 10;
SELECT * FROM fn_q02_videos_mais_comentados(
           (SELECT id_canal FROM Canal WHERE nome = 'GamerTV'));

-- Q3: canais por interações (todos e de um streamer)
SELECT * FROM fn_q03_canais_mais_interacoes() LIMIT 10;
SELECT * FROM fn_q03_canais_mais_interacoes('ana_fan');

-- Q4: média de doação por canal (todas e plataforma 2)
SELECT * FROM fn_q04_canais_media_doacao() LIMIT 10;
SELECT * FROM fn_q04_canais_media_doacao(2) LIMIT 10;

-- Q5: patrocínios por empresa (todas e uma empresa)
SELECT * FROM fn_q05_patrocinios_por_empresa() LIMIT 10;
SELECT * FROM fn_q05_patrocinios_por_empresa(
           (SELECT nro_empresa FROM Patrocinio LIMIT 1));

-- Q6: membros por usuário (todos e um usuário)
SELECT * FROM fn_q06_membros_por_usuario() LIMIT 10;
SELECT * FROM fn_q06_membros_por_usuario('pedro_gg');

-- Q7: canais com doações (todos e um canal)
SELECT * FROM fn_q07_canais_com_doacoes() LIMIT 10;
SELECT * FROM fn_q07_canais_com_doacoes(
           (SELECT id_canal FROM Canal WHERE nome = 'GamerTV'));

-- Q8 a Q11: top-k (k = 5)
SELECT * FROM fn_q08_top_canais_patrocinio(5);
SELECT * FROM fn_q09_top_canais_membros(5);
SELECT * FROM fn_q10_top_canais_doacoes(5);
SELECT * FROM fn_q11_top_canais_faturamento(5);

-- k inválido (descomente para ver o erro "Q8: k deve ser um inteiro positivo")
-- SELECT * FROM fn_q08_top_canais_patrocinio(0);

-- Q12: plataformas (top 3, e só a plataforma 1)
SELECT * FROM fn_q12_top_plataformas(3);
SELECT * FROM fn_q12_top_plataformas(3, 1);


-- ---------------------------------------------------------------------
-- Conferências: os dois valores de cada linha devem ser iguais
-- ---------------------------------------------------------------------

-- Q3: soma das interações dos canais = total de comentários
SELECT (SELECT SUM(total_interacoes) FROM fn_q03_canais_mais_interacoes()) AS pela_function,
       (SELECT COUNT(*) FROM Comentario)                                    AS direto;

-- Q10: soma das doações dos canais = soma das doações não recusadas
SELECT (SELECT SUM(soma_usd) FROM fn_q10_top_canais_doacoes(1000000)) AS pela_function,
       (SELECT SUM(valor) FROM Doacao WHERE status <> 'recusado')  AS direto;

-- Q11: o canal que mais fatura, recalculado a partir das tabelas cruas
WITH t AS (SELECT * FROM fn_q11_top_canais_faturamento(1))
SELECT t.id_canal,
       t.total AS pela_function,
       (SELECT COALESCE(SUM(p.valor), 0) FROM Patrocinio p WHERE p.id_canal = t.id_canal)
     + (SELECT COALESCE(SUM(n.valor), 0)
          FROM Inscricao i
          JOIN NivelCanal n ON n.id_canal = i.id_canal AND n.nivel = i.nivel
         WHERE i.id_canal = t.id_canal)
     + (SELECT COALESCE(SUM(d.valor), 0)
          FROM Doacao d
          JOIN Comentario co ON co.id_comentario = d.id_comentario
          JOIN Video v       ON v.id_video       = co.id_video
         WHERE v.id_canal = t.id_canal AND d.status <> 'recusado') AS recalculado
  FROM t;

-- Q12: soma dos canais por plataforma = total de canais
SELECT (SELECT SUM(qtd_canais) FROM fn_q12_top_plataformas(NULL)) AS pela_function,
       (SELECT COUNT(*) FROM Canal)                               AS direto;
