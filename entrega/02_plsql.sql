-- =====================================================================
-- PROJETO DE BANCO DE DADOS 2026/2 - UFF - Prof. Marcos Bedo
-- Arquivo 2: PL/pgSQL (triggers, views, functions/procedures)
--
-- Regras "verificado no COMMIT" usam CONSTRAINT TRIGGER DEFERRABLE
-- INITIALLY DEFERRED: a checagem só roda no fim da transação. Por isso a
-- carga de dados roda em uma única transação (BEGIN ... COMMIT).
-- =====================================================================


-- #####################################################################
-- PARTE 1 - TRIGGERS
-- #####################################################################

-- ---------------------------------------------------------------------
-- T1: mantém plataforma.qtd_users ao inserir, apagar ou mover contas
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_t1_qtd_users() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE plataforma SET qtd_users = qtd_users + 1
         WHERE nro_plataforma = NEW.nro_plataforma;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE plataforma SET qtd_users = qtd_users - 1
         WHERE nro_plataforma = OLD.nro_plataforma;
    ELSE  -- UPDATE: conta movida de plataforma
        IF NEW.nro_plataforma IS DISTINCT FROM OLD.nro_plataforma THEN
            UPDATE plataforma SET qtd_users = qtd_users - 1
             WHERE nro_plataforma = OLD.nro_plataforma;
            UPDATE plataforma SET qtd_users = qtd_users + 1
             WHERE nro_plataforma = NEW.nro_plataforma;
        END IF;
    END IF;
    RETURN NULL;
END $$;

CREATE TRIGGER trg_t01_qtd_users
AFTER INSERT OR DELETE OR UPDATE OF nro_plataforma ON plataforma_usuario
FOR EACH ROW EXECUTE FUNCTION fn_t1_qtd_users();


-- ---------------------------------------------------------------------
-- T2: mantém canal.qtd_videos e canal.qtd_visualizacoes a partir dos vídeos
-- (recalcula o canal afetado: simples e sem risco de divergência)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_recalcular_canal(p_id_canal integer) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE canal c
       SET qtd_videos        = (SELECT COUNT(*) FROM video v WHERE v.id_canal = c.id_canal),
           qtd_visualizacoes = (SELECT COALESCE(SUM(v.visu_total), 0) FROM video v WHERE v.id_canal = c.id_canal)
     WHERE c.id_canal = p_id_canal;
END $$;

CREATE OR REPLACE FUNCTION fn_t2_totais_canal() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        PERFORM fn_recalcular_canal(NEW.id_canal);
    ELSIF TG_OP = 'DELETE' THEN
        PERFORM fn_recalcular_canal(OLD.id_canal);
    ELSE  -- UPDATE
        PERFORM fn_recalcular_canal(NEW.id_canal);
        IF OLD.id_canal <> NEW.id_canal THEN
            PERFORM fn_recalcular_canal(OLD.id_canal);
        END IF;
    END IF;
    RETURN NULL;
END $$;

CREATE TRIGGER trg_t02_totais_canal
AFTER INSERT OR DELETE OR UPDATE OF id_canal, visu_total ON video
FOR EACH ROW EXECUTE FUNCTION fn_t2_totais_canal();


-- ---------------------------------------------------------------------
-- T3: todo canal novo nasce com os 5 níveis de membro
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_t3_niveis_padrao() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO nivel_canal (id_canal, nivel, nome, valor, gif)
    SELECT NEW.id_canal,
           n,
           (ARRAY['Bronze','Prata','Ouro','Platina','Diamante'])[n],
           (ARRAY[5, 10, 25, 50, 100]::numeric[])[n],
           'canal_' || NEW.id_canal || '_nivel_' || n || '.gif'
      FROM generate_series(1, 5) AS n;
    RETURN NULL;
END $$;

CREATE TRIGGER trg_t03_niveis_padrao
AFTER INSERT ON canal
FOR EACH ROW EXECUTE FUNCTION fn_t3_niveis_padrao();


-- ---------------------------------------------------------------------
-- T12: canal não pode ficar com menos de 5 níveis (verificado no COMMIT)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_chk_5_niveis(p_id_canal integer) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM canal WHERE id_canal = p_id_canal)
       AND (SELECT COUNT(*) FROM nivel_canal WHERE id_canal = p_id_canal) <> 5 THEN
        RAISE EXCEPTION 'T12: o canal % deve ter exatamente 5 níveis de membro', p_id_canal;
    END IF;
END $$;

CREATE OR REPLACE FUNCTION fn_t12_canal_5_niveis() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_TABLE_NAME = 'canal' THEN
        PERFORM fn_chk_5_niveis(NEW.id_canal);
    ELSE
        PERFORM fn_chk_5_niveis(OLD.id_canal);
        IF TG_OP = 'UPDATE' THEN
            IF NEW.id_canal <> OLD.id_canal THEN
                PERFORM fn_chk_5_niveis(NEW.id_canal);
            END IF;
        END IF;
    END IF;
    RETURN NULL;
END $$;

CREATE CONSTRAINT TRIGGER trg_t12_canal
AFTER INSERT ON canal
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION fn_t12_canal_5_niveis();

CREATE CONSTRAINT TRIGGER trg_t12_nivel
AFTER DELETE OR UPDATE OF id_canal ON nivel_canal
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION fn_t12_canal_5_niveis();


-- ---------------------------------------------------------------------
-- T4: vídeo não pode ser anterior ao início do canal
--     (inserir, mudar a data do vídeo ou movê-lo para outro canal)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_t4_video_data() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_inicio date;
BEGIN
    SELECT data_inicio INTO v_inicio FROM canal WHERE id_canal = NEW.id_canal;
    IF FOUND AND NEW.data_hora::date < v_inicio THEN
        RAISE EXCEPTION 'T4: o vídeo (%) não pode ser anterior ao início do canal % (%)',
                        NEW.data_hora, NEW.id_canal, v_inicio;
    END IF;

    -- mudar a data do vídeo não pode deixar comentário anterior à postagem (T7)
    IF TG_OP = 'UPDATE' THEN
        IF NEW.data_hora IS DISTINCT FROM OLD.data_hora THEN
            IF EXISTS (SELECT 1 FROM comentario
                        WHERE id_video = NEW.id_video AND data_hora < NEW.data_hora) THEN
                RAISE EXCEPTION 'T4/T7: o vídeo % possui comentários anteriores à nova data de postagem', NEW.id_video;
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_t04_video_data
BEFORE INSERT OR UPDATE OF data_hora, id_canal ON video
FOR EACH ROW EXECUTE FUNCTION fn_t4_video_data();


-- ---------------------------------------------------------------------
-- T14: mudar a data de início ou o dono de um canal não pode quebrar
--      regras já existentes (T4, T5, T6; T10 e T15 têm triggers próprios)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_t14_canal_update() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.data_inicio IS DISTINCT FROM OLD.data_inicio THEN
        IF EXISTS (SELECT 1 FROM video
                    WHERE id_canal = NEW.id_canal
                      AND data_hora::date < NEW.data_inicio) THEN
            RAISE EXCEPTION 'T14/T4: o canal % possui vídeos anteriores à nova data de início %',
                            NEW.id_canal, NEW.data_inicio;
        END IF;
    END IF;

    IF NEW.nick_streamer IS DISTINCT FROM OLD.nick_streamer THEN
        IF EXISTS (SELECT 1
                     FROM participa p
                     JOIN video v ON v.id_video = p.id_video
                    WHERE v.id_canal = NEW.id_canal
                      AND p.nick_streamer = NEW.nick_streamer) THEN
            RAISE EXCEPTION 'T14/T5: % é convidado de vídeos do canal % e não pode ser o novo dono',
                            NEW.nick_streamer, NEW.id_canal;
        END IF;
        IF EXISTS (SELECT 1 FROM inscricao
                    WHERE id_canal = NEW.id_canal
                      AND nick_membro = NEW.nick_streamer) THEN
            RAISE EXCEPTION 'T14/T6: % é membro do canal % e não pode ser o novo dono',
                            NEW.nick_streamer, NEW.id_canal;
        END IF;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_t14_canal_update
BEFORE UPDATE OF data_inicio, nick_streamer ON canal
FOR EACH ROW EXECUTE FUNCTION fn_t14_canal_update();


-- ---------------------------------------------------------------------
-- T5: o dono do canal não pode constar como convidado do próprio vídeo
--     (também ao mover o vídeo para outro canal)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_t5_convidado() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_dono varchar;
BEGIN
    SELECT c.nick_streamer INTO v_dono
      FROM video v JOIN canal c ON c.id_canal = v.id_canal
     WHERE v.id_video = NEW.id_video;
    IF v_dono = NEW.nick_streamer THEN
        RAISE EXCEPTION 'T5: % é dono do canal e não pode ser convidado do próprio vídeo %',
                        NEW.nick_streamer, NEW.id_video;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_t05_convidado
BEFORE INSERT OR UPDATE OF id_video, nick_streamer ON participa
FOR EACH ROW EXECUTE FUNCTION fn_t5_convidado();

CREATE OR REPLACE FUNCTION fn_t5_mover_video() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (SELECT 1
                 FROM participa p
                 JOIN canal c ON c.id_canal = NEW.id_canal
                WHERE p.id_video = NEW.id_video
                  AND p.nick_streamer = c.nick_streamer) THEN
        RAISE EXCEPTION 'T5: o dono do canal destino é convidado do vídeo %', NEW.id_video;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_t05_mover_video
BEFORE UPDATE OF id_canal ON video
FOR EACH ROW EXECUTE FUNCTION fn_t5_mover_video();


-- ---------------------------------------------------------------------
-- T6: o dono do canal não pode ser membro dele
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_t6_membro() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_dono varchar;
BEGIN
    SELECT nick_streamer INTO v_dono FROM canal WHERE id_canal = NEW.id_canal;
    IF v_dono = NEW.nick_membro THEN
        RAISE EXCEPTION 'T6: % é dono do canal % e não pode ser membro dele',
                        NEW.nick_membro, NEW.id_canal;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_t06_membro
BEFORE INSERT OR UPDATE OF nick_membro, id_canal ON inscricao
FOR EACH ROW EXECUTE FUNCTION fn_t6_membro();


-- ---------------------------------------------------------------------
-- T7: numera o comentário por vídeo (1,2,3...), exige data >= postagem do
--     vídeo e impede alterar id_video e seq
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_t7_comentario() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_postagem timestamp;
BEGIN
    IF TG_OP = 'INSERT' THEN
        -- trava a linha do vídeo: serializa a numeração concorrente
        SELECT data_hora INTO v_postagem
          FROM video WHERE id_video = NEW.id_video
           FOR NO KEY UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'T7: vídeo % inexistente', NEW.id_video;
        END IF;
        IF NEW.data_hora < v_postagem THEN
            RAISE EXCEPTION 'T7: o comentário (%) não pode ser anterior à postagem do vídeo (%)',
                            NEW.data_hora, v_postagem;
        END IF;
        SELECT COALESCE(MAX(seq), 0) + 1 INTO NEW.seq
          FROM comentario WHERE id_video = NEW.id_video;
    ELSE
        IF NEW.id_video IS DISTINCT FROM OLD.id_video OR NEW.seq IS DISTINCT FROM OLD.seq THEN
            RAISE EXCEPTION 'T7: id_video e seq do comentário não podem ser alterados';
        END IF;
        IF NEW.data_hora IS DISTINCT FROM OLD.data_hora THEN
            SELECT data_hora INTO v_postagem FROM video WHERE id_video = NEW.id_video;
            IF NEW.data_hora < v_postagem THEN
                RAISE EXCEPTION 'T7: o comentário (%) não pode ser anterior à postagem do vídeo (%)',
                                NEW.data_hora, v_postagem;
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_t07_comentario
BEFORE INSERT OR UPDATE ON comentario
FOR EACH ROW EXECUTE FUNCTION fn_t7_comentario();


-- ---------------------------------------------------------------------
-- T8: numera seq_pg (doação) por comentário
-- T8b: numera seq_plataforma (mecanismo da plataforma) por comentário
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_t8_seq_pg() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    -- trava o comentário para serializar a numeração concorrente
    PERFORM 1 FROM comentario
     WHERE id_video = NEW.id_video AND seq = NEW.seq_comentario
       FOR NO KEY UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'T8: comentário (%, %) inexistente', NEW.id_video, NEW.seq_comentario;
    END IF;
    SELECT COALESCE(MAX(seq_pg), 0) + 1 INTO NEW.seq_pg
      FROM doacao
     WHERE id_video = NEW.id_video AND seq_comentario = NEW.seq_comentario;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_t08_seq_pg
BEFORE INSERT ON doacao
FOR EACH ROW EXECUTE FUNCTION fn_t8_seq_pg();

CREATE OR REPLACE FUNCTION fn_t8b_seq_plataforma() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM 1 FROM comentario
     WHERE id_video = NEW.id_video AND seq = NEW.seq_comentario
       FOR NO KEY UPDATE;
    SELECT COALESCE(MAX(seq_plataforma), 0) + 1 INTO NEW.seq_plataforma
      FROM mecanismo_plat
     WHERE id_video = NEW.id_video AND seq_comentario = NEW.seq_comentario;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_t08b_seq_plataforma
BEFORE INSERT ON mecanismo_plat
FOR EACH ROW EXECUTE FUNCTION fn_t8b_seq_plataforma();


-- ---------------------------------------------------------------------
-- T16: converte a doação para USD no momento do INSERT (moeda do país de
--      residência de quem comentou) e torna o valor imutável depois disso
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_t16_conversao_doacao() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_moeda varchar;
    v_fator numeric;
BEGIN
    IF TG_OP = 'INSERT' THEN
        SELECT cv.moeda, cv.fator_conver
          INTO v_moeda, v_fator
          FROM comentario c
          JOIN usuario  u  ON u.nick = c.nick_usuario
          JOIN pais     p  ON p.ddi  = u.pais_residencia
          JOIN conversao cv ON cv.moeda = p.moeda
         WHERE c.id_video = NEW.id_video
           AND c.seq      = NEW.seq_comentario;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'T16: não foi possível obter a moeda da doação (comentário %, % inexistente)',
                            NEW.id_video, NEW.seq_comentario;
        END IF;
        NEW.moeda     := v_moeda;                                     -- sobrescreve qualquer valor informado
        NEW.valor_usd := ROUND(NEW.valor_original * v_fator, 4);
    ELSE
        IF NEW.valor_original IS DISTINCT FROM OLD.valor_original
           OR NEW.moeda       IS DISTINCT FROM OLD.moeda
           OR NEW.valor_usd   IS DISTINCT FROM OLD.valor_usd
           OR NEW.id_video    IS DISTINCT FROM OLD.id_video
           OR NEW.seq_comentario IS DISTINCT FROM OLD.seq_comentario
           OR NEW.seq_pg      IS DISTINCT FROM OLD.seq_pg THEN
            RAISE EXCEPTION 'T16: valor, moeda e identificação da doação são imutáveis (só o status muda)';
        END IF;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_t16_conversao_doacao
BEFORE INSERT OR UPDATE ON doacao
FOR EACH ROW EXECUTE FUNCTION fn_t16_conversao_doacao();


-- ---------------------------------------------------------------------
-- T13: uma doação aparece em no máximo uma forma de pagamento
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_t13_forma_unica() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF (TG_TABLE_NAME <> 'bitcoin' AND EXISTS (
            SELECT 1 FROM bitcoin x
             WHERE x.id_video = NEW.id_video AND x.seq_comentario = NEW.seq_comentario AND x.seq_pg = NEW.seq_pg))
    OR (TG_TABLE_NAME <> 'paypal' AND EXISTS (
            SELECT 1 FROM paypal x
             WHERE x.id_video = NEW.id_video AND x.seq_comentario = NEW.seq_comentario AND x.seq_pg = NEW.seq_pg))
    OR (TG_TABLE_NAME <> 'cartao_credito' AND EXISTS (
            SELECT 1 FROM cartao_credito x
             WHERE x.id_video = NEW.id_video AND x.seq_comentario = NEW.seq_comentario AND x.seq_pg = NEW.seq_pg))
    OR (TG_TABLE_NAME <> 'mecanismo_plat' AND EXISTS (
            SELECT 1 FROM mecanismo_plat x
             WHERE x.id_video = NEW.id_video AND x.seq_comentario = NEW.seq_comentario AND x.seq_pg = NEW.seq_pg))
    THEN
        RAISE EXCEPTION 'T13: a doação (%, %, %) já possui outra forma de pagamento',
                        NEW.id_video, NEW.seq_comentario, NEW.seq_pg;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_t13_bitcoin        BEFORE INSERT OR UPDATE ON bitcoin
FOR EACH ROW EXECUTE FUNCTION fn_t13_forma_unica();
CREATE TRIGGER trg_t13_paypal         BEFORE INSERT OR UPDATE ON paypal
FOR EACH ROW EXECUTE FUNCTION fn_t13_forma_unica();
CREATE TRIGGER trg_t13_cartao_credito BEFORE INSERT OR UPDATE ON cartao_credito
FOR EACH ROW EXECUTE FUNCTION fn_t13_forma_unica();
CREATE TRIGGER trg_t13_mecanismo_plat BEFORE INSERT OR UPDATE ON mecanismo_plat
FOR EACH ROW EXECUTE FUNCTION fn_t13_forma_unica();


-- ---------------------------------------------------------------------
-- T9a: uma doação tem exatamente uma forma de pagamento (verificado no COMMIT)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_chk_forma_pagamento(p_video integer, p_coment integer, p_pg integer) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
    v_qtd integer;
BEGIN
    IF EXISTS (SELECT 1 FROM doacao
                WHERE id_video = p_video AND seq_comentario = p_coment AND seq_pg = p_pg) THEN
        SELECT (SELECT COUNT(*) FROM bitcoin        WHERE id_video = p_video AND seq_comentario = p_coment AND seq_pg = p_pg)
             + (SELECT COUNT(*) FROM paypal         WHERE id_video = p_video AND seq_comentario = p_coment AND seq_pg = p_pg)
             + (SELECT COUNT(*) FROM cartao_credito WHERE id_video = p_video AND seq_comentario = p_coment AND seq_pg = p_pg)
             + (SELECT COUNT(*) FROM mecanismo_plat WHERE id_video = p_video AND seq_comentario = p_coment AND seq_pg = p_pg)
          INTO v_qtd;
        IF v_qtd <> 1 THEN
            RAISE EXCEPTION 'T9a: a doação (%, %, %) deve ter exatamente uma forma de pagamento (tem %)',
                            p_video, p_coment, p_pg, v_qtd;
        END IF;
    END IF;
END $$;

CREATE OR REPLACE FUNCTION fn_t9a_forma_obrigatoria() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        PERFORM fn_chk_forma_pagamento(NEW.id_video, NEW.seq_comentario, NEW.seq_pg);
    END IF;
    IF TG_OP IN ('DELETE', 'UPDATE') THEN
        PERFORM fn_chk_forma_pagamento(OLD.id_video, OLD.seq_comentario, OLD.seq_pg);
    END IF;
    RETURN NULL;
END $$;

CREATE CONSTRAINT TRIGGER trg_t09a_doacao
AFTER INSERT ON doacao
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION fn_t9a_forma_obrigatoria();

CREATE CONSTRAINT TRIGGER trg_t09a_bitcoin
AFTER DELETE OR UPDATE ON bitcoin
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION fn_t9a_forma_obrigatoria();
CREATE CONSTRAINT TRIGGER trg_t09a_paypal
AFTER DELETE OR UPDATE ON paypal
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION fn_t9a_forma_obrigatoria();
CREATE CONSTRAINT TRIGGER trg_t09a_cartao_credito
AFTER DELETE OR UPDATE ON cartao_credito
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION fn_t9a_forma_obrigatoria();
CREATE CONSTRAINT TRIGGER trg_t09a_mecanismo_plat
AFTER DELETE OR UPDATE ON mecanismo_plat
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION fn_t9a_forma_obrigatoria();


-- ---------------------------------------------------------------------
-- T9b: toda empresa tem ao menos um país de origem (verificado no COMMIT)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_chk_empresa_pais(p_id_empresa integer) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM empresa WHERE id_empresa = p_id_empresa)
       AND NOT EXISTS (SELECT 1 FROM empresa_pais WHERE id_empresa = p_id_empresa) THEN
        RAISE EXCEPTION 'T9b: a empresa % deve ter ao menos um país de origem', p_id_empresa;
    END IF;
END $$;

CREATE OR REPLACE FUNCTION fn_t9b_empresa_pais() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_TABLE_NAME = 'empresa' THEN
        PERFORM fn_chk_empresa_pais(NEW.id_empresa);
    ELSE
        PERFORM fn_chk_empresa_pais(OLD.id_empresa);
    END IF;
    RETURN NULL;
END $$;

CREATE CONSTRAINT TRIGGER trg_t09b_empresa
AFTER INSERT ON empresa
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION fn_t9b_empresa_pais();

CREATE CONSTRAINT TRIGGER trg_t09b_empresa_pais
AFTER DELETE OR UPDATE OF id_empresa ON empresa_pais
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION fn_t9b_empresa_pais();


-- ---------------------------------------------------------------------
-- T10: dono de canal e convidado de vídeo precisam ter passaporte
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_t10_passaporte() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM streamer_pais WHERE nick_streamer = NEW.nick_streamer) THEN
        RAISE EXCEPTION 'T10: % não possui passaporte e não pode ser dono de canal nem convidado', NEW.nick_streamer;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_t10_canal
BEFORE INSERT OR UPDATE OF nick_streamer ON canal
FOR EACH ROW EXECUTE FUNCTION fn_t10_passaporte();

CREATE TRIGGER trg_t10_participa
BEFORE INSERT OR UPDATE OF nick_streamer ON participa
FOR EACH ROW EXECUTE FUNCTION fn_t10_passaporte();


-- ---------------------------------------------------------------------
-- T11: não deixa apagar o último passaporte de quem é dono de canal
--      ou convidado de vídeo
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_t11_ultimo_passaporte() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF NEW.nick_streamer = OLD.nick_streamer THEN
            RETURN NEW;                               -- o dono do passaporte não mudou
        END IF;
    END IF;
    IF (SELECT COUNT(*) FROM streamer_pais WHERE nick_streamer = OLD.nick_streamer) = 1
       AND (EXISTS (SELECT 1 FROM canal    WHERE nick_streamer = OLD.nick_streamer)
         OR EXISTS (SELECT 1 FROM participa WHERE nick_streamer = OLD.nick_streamer)) THEN
        RAISE EXCEPTION 'T11: este é o último passaporte de %, que é dono de canal ou convidado de vídeo',
                        OLD.nick_streamer;
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_t11_ultimo_passaporte
BEFORE DELETE OR UPDATE OF nick_streamer ON streamer_pais
FOR EACH ROW EXECUTE FUNCTION fn_t11_ultimo_passaporte();


-- ---------------------------------------------------------------------
-- T15: todo streamer (com passaporte) tem ao menos um canal
--      (verificado no COMMIT)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_chk_streamer_canal(p_nick varchar) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM streamer_pais WHERE nick_streamer = p_nick)
       AND NOT EXISTS (SELECT 1 FROM canal WHERE nick_streamer = p_nick) THEN
        RAISE EXCEPTION 'T15: o streamer % deve ter ao menos um canal', p_nick;
    END IF;
END $$;

CREATE OR REPLACE FUNCTION fn_t15_streamer_canal() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_TABLE_NAME = 'streamer_pais' THEN
        PERFORM fn_chk_streamer_canal(NEW.nick_streamer);
    ELSE                                              -- canal apagado ou trocou de dono
        PERFORM fn_chk_streamer_canal(OLD.nick_streamer);
    END IF;
    RETURN NULL;
END $$;

CREATE CONSTRAINT TRIGGER trg_t15_streamer
AFTER INSERT OR UPDATE OF nick_streamer ON streamer_pais
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION fn_t15_streamer_canal();

CREATE CONSTRAINT TRIGGER trg_t15_canal
AFTER DELETE OR UPDATE OF nick_streamer ON canal
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION fn_t15_streamer_canal();


-- #####################################################################
-- PARTE 2 - VISÕES (5): 2 materializadas e 3 virtuais
-- Obs.: nenhuma visão materializada tem índice próprio, para respeitar o
-- limite de 5 índices (4 já usados). Por isso o refresh é o completo
-- (sp_atualizar_visoes), não o CONCURRENTLY.
-- #####################################################################

-- Comentários por vídeo (online/offline/total). LEFT JOIN mantém vídeos sem
-- comentário. Alimenta Q2 e Q3.
CREATE MATERIALIZED VIEW mv_video_comentarios AS
SELECT v.id_video,
       v.id_canal,
       COUNT(c.seq) FILTER (WHERE c.coment_on)     AS qtd_online,
       COUNT(c.seq) FILTER (WHERE NOT c.coment_on) AS qtd_offline,
       COUNT(c.seq)                                AS qtd_total
  FROM video v
  LEFT JOIN comentario c ON c.id_video = v.id_video
 GROUP BY v.id_video, v.id_canal;

-- Doações por canal, já em USD (valor_usd é gravado pelo trigger T16).
-- Doações 'recusado' não entram na arrecadação. Alimenta Q4, Q7, Q10 e Q11.
-- qtd_comentarios_com_doacao é a base da média "por comentário" (Q4).
CREATE MATERIALIZED VIEW mv_canal_doacoes AS
SELECT v.id_canal,
       COUNT(*)                                         AS qtd_doacoes,
       COUNT(DISTINCT (d.id_video, d.seq_comentario))   AS qtd_comentarios_com_doacao,
       SUM(d.valor_usd)                                 AS valor_total_usd
  FROM doacao d
  JOIN video v ON v.id_video = d.id_video
 WHERE d.status <> 'recusado'
 GROUP BY v.id_canal;

-- Patrocínio vigente por canal (tabela pequena: virtual, sempre atual).
CREATE VIEW vw_canal_patrocinio AS
SELECT p.id_canal,
       COUNT(*)     AS qtd_patrocinios,
       SUM(p.valor) AS valor_total_usd
  FROM patrocinio p
 GROUP BY p.id_canal;

-- Membros vigentes por canal e aporte mensal (virtual: entram e saem a
-- qualquer momento).
CREATE VIEW vw_canal_membros AS
SELECT i.id_canal,
       COUNT(*)     AS qtd_membros,
       SUM(n.valor) AS valor_mensal_usd
  FROM inscricao i
  JOIN nivel_canal n ON n.id_canal = i.id_canal AND n.nivel = i.nivel
 GROUP BY i.id_canal;

-- Faturamento por canal nas três fontes (patrocínio + membros/mês + doações).
CREATE VIEW vw_canal_faturamento AS
SELECT c.id_canal,
       COALESCE(p.valor_total_usd, 0)   AS patrocinio_usd,
       COALESCE(m.valor_mensal_usd, 0)  AS membros_usd,
       COALESCE(d.valor_total_usd, 0)   AS doacoes_usd,
       COALESCE(p.valor_total_usd, 0)
     + COALESCE(m.valor_mensal_usd, 0)
     + COALESCE(d.valor_total_usd, 0)   AS faturamento_total_usd
  FROM canal c
  LEFT JOIN vw_canal_patrocinio p ON p.id_canal = c.id_canal
  LEFT JOIN vw_canal_membros    m ON m.id_canal = c.id_canal
  LEFT JOIN mv_canal_doacoes    d ON d.id_canal = c.id_canal;

-- Atualiza as visões materializadas (chamar após cargas e antes das consultas)
CREATE OR REPLACE PROCEDURE sp_atualizar_visoes()
LANGUAGE plpgsql AS $$
BEGIN
    REFRESH MATERIALIZED VIEW mv_video_comentarios;
    REFRESH MATERIALIZED VIEW mv_canal_doacoes;
END $$;


-- #####################################################################
-- PARTE 3 - CONSULTAS (functions parametrizadas)
-- Obs.: no PostgreSQL uma PROCEDURE não devolve conjunto de linhas; por
-- isso as consultas são FUNCTIONS RETURNS TABLE com parâmetro opcional
-- (DEFAULT NULL = sem filtro). Q2, Q3, Q4, Q7, Q10 e Q11 leem as
-- materializadas: rode CALL sp_atualizar_visoes() antes.
-- #####################################################################

-- Q1: streamers com mais vídeos publicados (vídeos dos canais que possuem)
--     e soma das visualizações. Filtro opcional: plataforma.
CREATE OR REPLACE FUNCTION fn_q1_streamers_mais_videos(p_nro_plataforma integer DEFAULT NULL)
RETURNS TABLE (nick_streamer varchar, qtd_videos bigint, soma_visualizacoes bigint)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
BEGIN
    RETURN QUERY
    SELECT c.nick_streamer,
           SUM(c.qtd_videos)::bigint,
           SUM(c.qtd_visualizacoes)::bigint
      FROM canal c
     WHERE p_nro_plataforma IS NULL OR c.nro_plataforma = p_nro_plataforma
     GROUP BY c.nick_streamer
     ORDER BY 2 DESC, 3 DESC, 1;
END $$;

-- Q2: vídeos com mais comentários (online, offline, total).
--     Filtro opcional: canal.
CREATE OR REPLACE FUNCTION fn_q2_videos_mais_comentados(p_id_canal integer DEFAULT NULL)
RETURNS TABLE (id_video integer, titulo varchar, canal_nome varchar,
               qtd_online bigint, qtd_offline bigint, qtd_total bigint)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
BEGIN
    RETURN QUERY
    SELECT v.id_video, v.titulo, c.nome,
           m.qtd_online, m.qtd_offline, m.qtd_total
      FROM mv_video_comentarios m
      JOIN video v ON v.id_video = m.id_video
      JOIN canal c ON c.id_canal = m.id_canal
     WHERE p_id_canal IS NULL OR m.id_canal = p_id_canal
     ORDER BY m.qtd_total DESC, v.id_video;
END $$;

-- Q3: canais por total de interações (comentários online + offline) e
--     média por vídeo. Filtro opcional: streamer (dono).
CREATE OR REPLACE FUNCTION fn_q3_canais_interacoes(p_nick_streamer varchar DEFAULT NULL)
RETURNS TABLE (id_canal integer, canal_nome varchar, plataforma_nome varchar,
               qtd_videos bigint, total_interacoes bigint, media_interacoes_por_video numeric)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
BEGIN
    RETURN QUERY
    SELECT c.id_canal, c.nome, p.nome,
           COUNT(m.id_video),
           COALESCE(SUM(m.qtd_total), 0)::bigint,
           COALESCE(ROUND(SUM(m.qtd_total)::numeric / NULLIF(COUNT(m.id_video), 0), 2), 0)
      FROM canal c
      JOIN plataforma p ON p.nro_plataforma = c.nro_plataforma
      LEFT JOIN mv_video_comentarios m ON m.id_canal = c.id_canal
     WHERE p_nick_streamer IS NULL OR c.nick_streamer = p_nick_streamer
     GROUP BY c.id_canal, c.nome, p.nome
     ORDER BY 5 DESC, 1;
END $$;

-- Q4: canais pelo valor médio (USD) das doações por comentário que recebeu
--     doação, com quantidade de doações e valor total.
--     Filtro opcional: plataforma.
CREATE OR REPLACE FUNCTION fn_q4_canais_media_doacao(p_nro_plataforma integer DEFAULT NULL)
RETURNS TABLE (id_canal integer, canal_nome varchar, qtd_doacoes bigint,
               valor_total_usd numeric, valor_medio_por_comentario_usd numeric)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
BEGIN
    RETURN QUERY
    SELECT c.id_canal, c.nome, d.qtd_doacoes, d.valor_total_usd,
           ROUND(d.valor_total_usd / d.qtd_comentarios_com_doacao, 4)
      FROM mv_canal_doacoes d
      JOIN canal c ON c.id_canal = d.id_canal
     WHERE p_nro_plataforma IS NULL OR c.nro_plataforma = p_nro_plataforma
     ORDER BY 5 DESC, 1;
END $$;

-- Q5: canais patrocinados e valores pagos, por empresa.
--     Filtro opcional: empresa.
CREATE OR REPLACE FUNCTION fn_q5_patrocinios_por_empresa(p_id_empresa integer DEFAULT NULL)
RETURNS TABLE (id_empresa integer, empresa_nome varchar, id_canal integer, canal_nome varchar,
               plataforma_nome varchar, valor_patrocinio_usd numeric, total_pago_empresa_usd numeric)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
BEGIN
    RETURN QUERY
    SELECT e.id_empresa, e.nome, c.id_canal, c.nome, pl.nome,
           pt.valor,
           SUM(pt.valor) OVER (PARTITION BY pt.id_empresa)
      FROM patrocinio pt
      JOIN empresa    e  ON e.id_empresa     = pt.id_empresa
      JOIN canal      c  ON c.id_canal       = pt.id_canal
      JOIN plataforma pl ON pl.nro_plataforma = c.nro_plataforma
     WHERE p_id_empresa IS NULL OR pt.id_empresa = p_id_empresa
     ORDER BY 7 DESC, 1, 6 DESC, 3;
END $$;

-- Q6: de quantos canais cada usuário é membro e quanto desembolsa por mês.
--     Filtro opcional: usuário.
CREATE OR REPLACE FUNCTION fn_q6_membros_por_usuario(p_nick_usuario varchar DEFAULT NULL)
RETURNS TABLE (nick_membro varchar, qtd_canais bigint, valor_mensal_usd numeric)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
BEGIN
    RETURN QUERY
    SELECT i.nick_membro, COUNT(*), SUM(n.valor)
      FROM inscricao i
      JOIN nivel_canal n ON n.id_canal = i.id_canal AND n.nivel = i.nivel
     WHERE p_nick_usuario IS NULL OR i.nick_membro = p_nick_usuario
     GROUP BY i.nick_membro
     ORDER BY 3 DESC, 1;
END $$;

-- Q7: canais que já receberam doações e a soma recebida (USD).
--     Filtro opcional: canal.
CREATE OR REPLACE FUNCTION fn_q7_canais_com_doacoes(p_id_canal integer DEFAULT NULL)
RETURNS TABLE (id_canal integer, canal_nome varchar, qtd_doacoes bigint, valor_total_usd numeric)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
BEGIN
    RETURN QUERY
    SELECT c.id_canal, c.nome, d.qtd_doacoes, d.valor_total_usd
      FROM mv_canal_doacoes d
      JOIN canal c ON c.id_canal = d.id_canal
     WHERE p_id_canal IS NULL OR d.id_canal = p_id_canal
     ORDER BY 4 DESC, 1;
END $$;

-- Q8: top-k canais que mais recebem patrocínio.
CREATE OR REPLACE FUNCTION fn_q8_top_k_patrocinio(p_k integer DEFAULT 10)
RETURNS TABLE (id_canal integer, canal_nome varchar, qtd_patrocinios bigint, valor_total_usd numeric)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
BEGIN
    IF p_k IS NULL OR p_k <= 0 THEN
        RAISE EXCEPTION 'Q8: k deve ser um inteiro positivo';
    END IF;
    RETURN QUERY
    SELECT c.id_canal, c.nome, v.qtd_patrocinios, v.valor_total_usd
      FROM vw_canal_patrocinio v
      JOIN canal c ON c.id_canal = v.id_canal
     ORDER BY 4 DESC, 1
     LIMIT p_k;
END $$;

-- Q9: top-k canais que mais recebem aportes de membros (valor mensal).
CREATE OR REPLACE FUNCTION fn_q9_top_k_membros(p_k integer DEFAULT 10)
RETURNS TABLE (id_canal integer, canal_nome varchar, qtd_membros bigint, valor_mensal_usd numeric)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
BEGIN
    IF p_k IS NULL OR p_k <= 0 THEN
        RAISE EXCEPTION 'Q9: k deve ser um inteiro positivo';
    END IF;
    RETURN QUERY
    SELECT c.id_canal, c.nome, v.qtd_membros, v.valor_mensal_usd
      FROM vw_canal_membros v
      JOIN canal c ON c.id_canal = v.id_canal
     ORDER BY 4 DESC, 1
     LIMIT p_k;
END $$;

-- Q10: top-k canais que mais receberam doações (todos os vídeos).
CREATE OR REPLACE FUNCTION fn_q10_top_k_doacoes(p_k integer DEFAULT 10)
RETURNS TABLE (id_canal integer, canal_nome varchar, qtd_doacoes bigint, valor_total_usd numeric)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
BEGIN
    IF p_k IS NULL OR p_k <= 0 THEN
        RAISE EXCEPTION 'Q10: k deve ser um inteiro positivo';
    END IF;
    RETURN QUERY
    SELECT c.id_canal, c.nome, d.qtd_doacoes, d.valor_total_usd
      FROM mv_canal_doacoes d
      JOIN canal c ON c.id_canal = d.id_canal
     ORDER BY 4 DESC, 1
     LIMIT p_k;
END $$;

-- Q11: top-k canais que mais faturam (patrocínio + membros + doações).
CREATE OR REPLACE FUNCTION fn_q11_top_k_faturamento(p_k integer DEFAULT 10)
RETURNS TABLE (id_canal integer, canal_nome varchar, patrocinio_usd numeric, membros_usd numeric,
               doacoes_usd numeric, faturamento_total_usd numeric)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
BEGIN
    IF p_k IS NULL OR p_k <= 0 THEN
        RAISE EXCEPTION 'Q11: k deve ser um inteiro positivo';
    END IF;
    RETURN QUERY
    SELECT c.id_canal, c.nome, f.patrocinio_usd, f.membros_usd, f.doacoes_usd, f.faturamento_total_usd
      FROM vw_canal_faturamento f
      JOIN canal c ON c.id_canal = f.id_canal
     ORDER BY 6 DESC, 1
     LIMIT p_k;
END $$;

-- Q12 (desafio): top-k plataformas pela quantidade de streamers E de canais
--     (streamers = donos distintos de canais da plataforma; empate no
--     número de streamers é desfeito pelo número de canais).
--     Filtro opcional: plataforma.
CREATE OR REPLACE FUNCTION fn_q12_top_k_plataformas(p_k integer DEFAULT NULL,
                                                    p_nro_plataforma integer DEFAULT NULL)
RETURNS TABLE (nro_plataforma integer, plataforma_nome varchar, qtd_streamers bigint, qtd_canais bigint)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
BEGIN
    IF p_k IS NOT NULL AND p_k <= 0 THEN
        RAISE EXCEPTION 'Q12: k deve ser um inteiro positivo';
    END IF;
    RETURN QUERY
    SELECT p.nro_plataforma, p.nome,
           COUNT(DISTINCT c.nick_streamer),
           COUNT(c.id_canal)
      FROM plataforma p
      LEFT JOIN canal c ON c.nro_plataforma = p.nro_plataforma
     WHERE p_nro_plataforma IS NULL OR p.nro_plataforma = p_nro_plataforma
     GROUP BY p.nro_plataforma, p.nome
     ORDER BY 3 DESC, 4 DESC, 1
     LIMIT p_k;
END $$;