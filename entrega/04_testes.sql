-- =====================================================================
-- PROJETO DE BANCO DE DADOS 2026/2 - UFF - Prof. Marcos Bedo
-- Arquivo 4: chamadas de teste (consultas Q1-Q12 e triggers)
-- Os valores de filtro são escolhidos por subconsultas, para sempre
-- existirem na carga gerada.
-- =====================================================================

CALL sp_atualizar_visoes();


-- #####################################################################
-- PARTE 1 - CONSULTAS
-- #####################################################################

-- ---- Q1: streamers com mais vídeos (sem filtro / filtrando uma plataforma) ----
SELECT * FROM fn_q1_streamers_mais_videos() LIMIT 10;
SELECT * FROM fn_q1_streamers_mais_videos(
         (SELECT nro_plataforma FROM canal GROUP BY nro_plataforma
           ORDER BY COUNT(*) DESC, nro_plataforma LIMIT 1)) LIMIT 10;

-- ---- Q2: vídeos com mais comentários (sem filtro / filtrando um canal) ----
SELECT * FROM fn_q2_videos_mais_comentados() LIMIT 10;
SELECT * FROM fn_q2_videos_mais_comentados(
         (SELECT id_canal FROM video GROUP BY id_canal
           ORDER BY COUNT(*) DESC, id_canal LIMIT 1)) LIMIT 10;

-- ---- Q3: canais por total de interações e média por vídeo ----
SELECT * FROM fn_q3_canais_interacoes() LIMIT 10;
SELECT * FROM fn_q3_canais_interacoes('user_1');

-- ---- Q4: canais por valor médio de doação por comentário ----
SELECT * FROM fn_q4_canais_media_doacao() LIMIT 10;
SELECT * FROM fn_q4_canais_media_doacao(
         (SELECT nro_plataforma FROM canal GROUP BY nro_plataforma
           ORDER BY COUNT(*) DESC, nro_plataforma LIMIT 1)) LIMIT 10;

-- ---- Q5: canais patrocinados e valores pagos por empresa ----
SELECT * FROM fn_q5_patrocinios_por_empresa() LIMIT 10;
SELECT * FROM fn_q5_patrocinios_por_empresa(
         (SELECT id_empresa FROM patrocinio ORDER BY valor DESC, id_empresa LIMIT 1));

-- ---- Q6: quantos canais cada usuário apoia e quanto paga por mês ----
SELECT * FROM fn_q6_membros_por_usuario() LIMIT 10;
SELECT * FROM fn_q6_membros_por_usuario('user_1001');

-- ---- Q7: canais que já receberam doações ----
SELECT * FROM fn_q7_canais_com_doacoes() LIMIT 10;
SELECT * FROM fn_q7_canais_com_doacoes(
         (SELECT id_canal FROM mv_canal_doacoes ORDER BY valor_total_usd DESC LIMIT 1));

-- ---- Q8: top-k patrocínio ----
SELECT * FROM fn_q8_top_k_patrocinio(5);

-- ---- Q9: top-k aportes de membros ----
SELECT * FROM fn_q9_top_k_membros(5);

-- ---- Q10: top-k doações ----
SELECT * FROM fn_q10_top_k_doacoes(5);

-- ---- Q11: top-k faturamento (patrocínio + membros + doações) ----
SELECT * FROM fn_q11_top_k_faturamento(5);

-- ---- Q12 (desafio): top-k plataformas por streamers e canais ----
SELECT * FROM fn_q12_top_k_plataformas(5);
SELECT * FROM fn_q12_top_k_plataformas(NULL, 1);        -- só a plataforma 1
SELECT * FROM fn_q12_top_k_plataformas(p_nro_plataforma => 1);

-- ---- k inválido deve falhar (erro esperado) ----
-- SELECT * FROM fn_q8_top_k_patrocinio(0);


-- #####################################################################
-- PARTE 2 - TRIGGERS
-- Cada teste roda dentro de BEGIN ... ROLLBACK (não altera os dados).
-- Os testes de bloqueio imprimem "OK (bloqueado)" quando o trigger barra a
-- operação. As regras verificadas no COMMIT são forçadas com
-- SET CONSTRAINTS ALL IMMEDIATE.
-- #####################################################################

-- ---- T1: mover conta entre plataformas ajusta qtd_users das duas ----
BEGIN;
SELECT nro_plataforma, qtd_users FROM plataforma WHERE nro_plataforma IN (1, 2) ORDER BY 1;
UPDATE plataforma_usuario SET nro_plataforma = 2
 WHERE nick_usuario = (SELECT nick_usuario FROM plataforma_usuario WHERE nro_plataforma = 1 LIMIT 1);
SELECT nro_plataforma, qtd_users FROM plataforma WHERE nro_plataforma IN (1, 2) ORDER BY 1;  -- 1 diminui, 2 aumenta
ROLLBACK;

-- ---- T2: inserir vídeo atualiza qtd_videos e qtd_visualizacoes do canal ----
BEGIN;
SELECT id_canal, qtd_videos, qtd_visualizacoes FROM canal WHERE id_canal = 1;
INSERT INTO video (id_canal, titulo, data_hora, tema, duracao, visu_simul, visu_total)
SELECT 1, 'teste T2', data_inicio::timestamp + INTERVAL '10 days', 'FPS', INTERVAL '1 hour', 10, 1000
  FROM canal WHERE id_canal = 1;
SELECT id_canal, qtd_videos, qtd_visualizacoes FROM canal WHERE id_canal = 1;  -- +1 vídeo, +1000 visualizações
ROLLBACK;

-- ---- T3 (+T12/T15 no commit): canal novo nasce com 5 níveis ----
BEGIN;
INSERT INTO canal (nome, nro_plataforma, nick_streamer, tipo, data_inicio, descricao)
VALUES ('canal_teste_t3', 1, 'user_1', 'publico', DATE '2024-01-01', 'teste');
SELECT n.nivel, n.nome, n.valor, n.gif
  FROM nivel_canal n JOIN canal c ON c.id_canal = n.id_canal
 WHERE c.nome = 'canal_teste_t3' ORDER BY n.nivel;                              -- 5 linhas
SET CONSTRAINTS ALL IMMEDIATE;                                                  -- não deve dar erro
ROLLBACK;

-- ---- T4: vídeo anterior ao início do canal ----
BEGIN;
DO $$
DECLARE v_ok boolean := false;
BEGIN
    BEGIN
        INSERT INTO video (id_canal, titulo, data_hora, tema, duracao, visu_simul, visu_total)
        SELECT id_canal, 'teste T4', data_inicio::timestamp - INTERVAL '1 day', 'FPS', INTERVAL '10 minutes', 1, 10
          FROM canal WHERE id_canal = 1;
    EXCEPTION WHEN raise_exception THEN v_ok := true;
    END;
    RAISE NOTICE 'T4  - %', CASE WHEN v_ok THEN 'OK (bloqueado)' ELSE 'FALHOU' END;
END $$;
ROLLBACK;

-- ---- T14: mover o início do canal para depois de seus vídeos ----
BEGIN;
DO $$
DECLARE v_ok boolean := false;
BEGIN
    BEGIN
        UPDATE canal SET data_inicio = DATE '2099-01-01'
         WHERE id_canal = (SELECT id_canal FROM video LIMIT 1);
    EXCEPTION WHEN raise_exception THEN v_ok := true;
    END;
    RAISE NOTICE 'T14 - %', CASE WHEN v_ok THEN 'OK (bloqueado)' ELSE 'FALHOU' END;
END $$;
ROLLBACK;

-- ---- T5: dono do canal como convidado do próprio vídeo ----
BEGIN;
DO $$
DECLARE v_ok boolean := false;
BEGIN
    BEGIN
        INSERT INTO participa (id_video, nick_streamer)
        SELECT v.id_video, c.nick_streamer
          FROM video v JOIN canal c ON c.id_canal = v.id_canal
         LIMIT 1;
    EXCEPTION WHEN raise_exception THEN v_ok := true;
    END;
    RAISE NOTICE 'T5  - %', CASE WHEN v_ok THEN 'OK (bloqueado)' ELSE 'FALHOU' END;
END $$;
ROLLBACK;

-- ---- T6: dono do canal como membro dele ----
BEGIN;
DO $$
DECLARE v_ok boolean := false;
BEGIN
    BEGIN
        INSERT INTO inscricao (nick_membro, id_canal, nivel)
        SELECT nick_streamer, id_canal, 1 FROM canal LIMIT 1;
    EXCEPTION WHEN raise_exception THEN v_ok := true;
    END;
    RAISE NOTICE 'T6  - %', CASE WHEN v_ok THEN 'OK (bloqueado)' ELSE 'FALHOU' END;
END $$;
ROLLBACK;

-- ---- T7: numeração do comentário (max+1 no vídeo) ----
BEGIN;
SELECT id_video, MAX(seq) AS ultimo_seq FROM comentario WHERE id_video = 1 GROUP BY id_video;
INSERT INTO comentario (id_video, nick_usuario, texto, data_hora, coment_on)
SELECT id_video, 'user_1', 'teste de numeração', data_hora + INTERVAL '1 hour', TRUE
  FROM video WHERE id_video = 1
RETURNING id_video, seq;                                                        -- seq = último + 1
ROLLBACK;

-- ---- T7: data anterior à postagem e alteração de seq são barradas ----
BEGIN;
DO $$
DECLARE v_ok boolean := false;
BEGIN
    BEGIN
        INSERT INTO comentario (id_video, nick_usuario, texto, data_hora, coment_on)
        SELECT id_video, 'user_1', 'cedo demais', data_hora - INTERVAL '1 day', TRUE
          FROM video LIMIT 1;
    EXCEPTION WHEN raise_exception THEN v_ok := true;
    END;
    RAISE NOTICE 'T7 (data)  - %', CASE WHEN v_ok THEN 'OK (bloqueado)' ELSE 'FALHOU' END;

    v_ok := false;
    BEGIN
        UPDATE comentario SET seq = 999
         WHERE (id_video, seq) = (SELECT id_video, seq FROM comentario LIMIT 1);
    EXCEPTION WHEN raise_exception THEN v_ok := true;
    END;
    RAISE NOTICE 'T7 (seq)   - %', CASE WHEN v_ok THEN 'OK (bloqueado)' ELSE 'FALHOU' END;
END $$;
ROLLBACK;

-- ---- T8 + T16: seq_pg automático e conversão para USD no INSERT ----
BEGIN;
INSERT INTO doacao (id_video, seq_comentario, valor_original, status)
SELECT id_video, seq, 100.00, 'recebido'
  FROM comentario ORDER BY id_video, seq LIMIT 1
RETURNING id_video, seq_comentario, seq_pg, valor_original, moeda, valor_usd;
ROLLBACK;

-- T16: a conversão confere com o fator da moeda (esperado = valor_usd)
SELECT d.id_video, d.seq_comentario, d.seq_pg, d.valor_original, d.moeda,
       cv.fator_conver, d.valor_usd, ROUND(d.valor_original * cv.fator_conver, 4) AS esperado
  FROM doacao d JOIN conversao cv ON cv.moeda = d.moeda
 LIMIT 5;

-- T16: valor é imutável depois do insert
BEGIN;
DO $$
DECLARE v_ok boolean := false;
BEGIN
    BEGIN
        UPDATE doacao SET valor_original = valor_original + 1
         WHERE (id_video, seq_comentario, seq_pg) =
               (SELECT id_video, seq_comentario, seq_pg FROM doacao LIMIT 1);
    EXCEPTION WHEN raise_exception THEN v_ok := true;
    END;
    RAISE NOTICE 'T16 - %', CASE WHEN v_ok THEN 'OK (bloqueado)' ELSE 'FALHOU' END;
END $$;
ROLLBACK;

-- ---- T8b: seq_plataforma automático (mecanismo da plataforma) ----
-- (a doação de teste é criada e ligada ao mecanismo na mesma transação)
BEGIN;
WITH nova AS (
    INSERT INTO doacao (id_video, seq_comentario, valor_original, status)
    SELECT id_video, seq, 50.00, 'lido'
      FROM comentario ORDER BY id_video, seq LIMIT 1
    RETURNING id_video, seq_comentario, seq_pg
)
INSERT INTO mecanismo_plat (id_video, seq_comentario, seq_pg)
SELECT id_video, seq_comentario, seq_pg FROM nova
RETURNING id_video, seq_comentario, seq_pg, seq_plataforma;
SET CONSTRAINTS ALL IMMEDIATE;                                                  -- T9a satisfeita: sem erro
ROLLBACK;

-- ---- T13: segunda forma de pagamento para a mesma doação ----
BEGIN;
DO $$
DECLARE v_ok boolean := false;
BEGIN
    BEGIN
        INSERT INTO paypal (id_video, seq_comentario, seq_pg, id_paypal)
        SELECT id_video, seq_comentario, seq_pg, 'PP-TESTE-T13' FROM bitcoin LIMIT 1;
    EXCEPTION WHEN raise_exception THEN v_ok := true;
    END;
    RAISE NOTICE 'T13 - %', CASE WHEN v_ok THEN 'OK (bloqueado)' ELSE 'FALHOU' END;
END $$;
ROLLBACK;

-- ---- T9a: doação sem forma de pagamento (checada no COMMIT) ----
BEGIN;
DO $$
DECLARE v_ok boolean := false;
BEGIN
    BEGIN
        INSERT INTO doacao (id_video, seq_comentario, valor_original, status)
        SELECT id_video, seq, 10.00, 'lido' FROM comentario LIMIT 1;
        SET CONSTRAINTS ALL IMMEDIATE;
    EXCEPTION WHEN raise_exception THEN v_ok := true;
    END;
    RAISE NOTICE 'T9a - %', CASE WHEN v_ok THEN 'OK (bloqueado)' ELSE 'FALHOU' END;
END $$;
ROLLBACK;

-- ---- T9b: empresa sem país de origem (checada no COMMIT) ----
BEGIN;
DO $$
DECLARE v_ok boolean := false;
BEGIN
    BEGIN
        INSERT INTO empresa (nome, nome_fantasia) VALUES ('Empresa sem pais', 'Sem Pais');
        SET CONSTRAINTS ALL IMMEDIATE;
    EXCEPTION WHEN raise_exception THEN v_ok := true;
    END;
    RAISE NOTICE 'T9b - %', CASE WHEN v_ok THEN 'OK (bloqueado)' ELSE 'FALHOU' END;
END $$;
ROLLBACK;

-- ---- T10: convidado sem passaporte (user_9000 não é streamer) ----
BEGIN;
DO $$
DECLARE v_ok boolean := false;
BEGIN
    BEGIN
        INSERT INTO participa (id_video, nick_streamer) VALUES (1, 'user_9000');
    EXCEPTION WHEN raise_exception THEN v_ok := true;
    END;
    RAISE NOTICE 'T10 - %', CASE WHEN v_ok THEN 'OK (bloqueado)' ELSE 'FALHOU' END;
END $$;
ROLLBACK;

-- ---- T11: apagar o último passaporte de um dono de canal (user_500 só tem um) ----
BEGIN;
DO $$
DECLARE v_ok boolean := false;
BEGIN
    BEGIN
        DELETE FROM streamer_pais WHERE nick_streamer = 'user_500';
    EXCEPTION WHEN raise_exception THEN v_ok := true;
    END;
    RAISE NOTICE 'T11 - %', CASE WHEN v_ok THEN 'OK (bloqueado)' ELSE 'FALHOU' END;
END $$;
ROLLBACK;

-- ---- T12: canal com menos de 5 níveis (checado no COMMIT) ----
BEGIN;
DO $$
DECLARE v_ok boolean := false;
BEGIN
    BEGIN
        DELETE FROM nivel_canal
         WHERE (id_canal, nivel) = (SELECT x.id_canal, x.nivel
                                      FROM nivel_canal x
                                     WHERE NOT EXISTS (SELECT 1 FROM inscricao i
                                                        WHERE i.id_canal = x.id_canal
                                                          AND i.nivel    = x.nivel)
                                     LIMIT 1);
        SET CONSTRAINTS ALL IMMEDIATE;
    EXCEPTION WHEN raise_exception THEN v_ok := true;
    END;
    RAISE NOTICE 'T12 - %', CASE WHEN v_ok THEN 'OK (bloqueado)' ELSE 'FALHOU' END;
END $$;
ROLLBACK;

-- ---- T15: streamer (com passaporte) sem canal (user_9999 não tem canal) ----
BEGIN;
DO $$
DECLARE v_ok boolean := false;
BEGIN
    BEGIN
        INSERT INTO streamer_pais (nick_streamer, ddi_pais, nro_passaporte)
        VALUES ('user_9999', 1, 'PTESTE-T15');
        SET CONSTRAINTS ALL IMMEDIATE;
    EXCEPTION WHEN raise_exception THEN v_ok := true;
    END;
    RAISE NOTICE 'T15 - %', CASE WHEN v_ok THEN 'OK (bloqueado)' ELSE 'FALHOU' END;
END $$;
ROLLBACK;
