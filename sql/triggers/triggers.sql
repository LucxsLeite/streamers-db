-- =====================================================================
-- PROJETO DE BANCO DE DADOS 2026/2 - UFF - Prof. Marcos Bedo
-- triggers.sql
-- =====================================================================
-- ORDEM DE EXECUÇÃO RECOMENDADA
--   create_database -> create_tables -> create_constraints -> insert_data
--   -> triggers.sql -> 03_pos_carga.sql -> create_views -> index
-- Os triggers entram DEPOIS da carga porque o insert_data.sql insere a
-- Doacao e suas subtabelas em comandos separados (o trigger de totalidade
-- da doação rejeitaria) e gera datas aleatórias que violariam T4/T7.
-- O 03_pos_carga.sql acerta o que a carga aleatória deixou fora das regras.
--
-- Estratégia de desempenho (mantida do rascunho):
--  * Atributos derivados são mantidos INCREMENTALMENTE. INSERT/DELETE usam
--    triggers de COMANDO com tabelas de transição (1 UPDATE agregado por
--    comando, não por linha).
--  * UPDATE usa trigger de linha com lista de colunas + WHEN.
--  * Regras que não cabem em FK/CHECK usam triggers BEFORE (linha) ou
--    CONSTRAINT TRIGGER deferidos (verificados no COMMIT).
-- =====================================================================

SET search_path TO public;

-- ---------------------------------------------------------------------
-- T1. Plataforma.qtd_users  <-  PlataformaUsuario           
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_pu_ins() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    UPDATE Plataforma p
       SET qtd_users = p.qtd_users + d.n
      FROM (SELECT nro_plataforma, count(*)::int AS n FROM novas GROUP BY nro_plataforma) d
     WHERE p.nro = d.nro_plataforma;
    RETURN NULL;
END $$;

CREATE OR REPLACE FUNCTION trg_pu_del() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    UPDATE Plataforma p
       SET qtd_users = p.qtd_users - d.n
      FROM (SELECT nro_plataforma, count(*)::int AS n FROM antigas GROUP BY nro_plataforma) d
     WHERE p.nro = d.nro_plataforma;
    RETURN NULL;
END $$;

CREATE OR REPLACE FUNCTION trg_pu_upd() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN   -- conta mudou de plataforma
    UPDATE Plataforma SET qtd_users = qtd_users - 1 WHERE nro = OLD.nro_plataforma;
    UPDATE Plataforma SET qtd_users = qtd_users + 1 WHERE nro = NEW.nro_plataforma;
    RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_pu_ai ON PlataformaUsuario;
DROP TRIGGER IF EXISTS trg_pu_ad ON PlataformaUsuario;
DROP TRIGGER IF EXISTS trg_pu_au ON PlataformaUsuario;
CREATE TRIGGER trg_pu_ai AFTER INSERT ON PlataformaUsuario
    REFERENCING NEW TABLE AS novas   FOR EACH STATEMENT EXECUTE FUNCTION trg_pu_ins();
CREATE TRIGGER trg_pu_ad AFTER DELETE ON PlataformaUsuario
    REFERENCING OLD TABLE AS antigas FOR EACH STATEMENT EXECUTE FUNCTION trg_pu_del();
CREATE TRIGGER trg_pu_au AFTER UPDATE OF nro_plataforma ON PlataformaUsuario
    FOR EACH ROW WHEN (OLD.nro_plataforma IS DISTINCT FROM NEW.nro_plataforma)
    EXECUTE FUNCTION trg_pu_upd();

-- ---------------------------------------------------------------------
-- T2. Canal.qtd_videos / Canal.qtd_visualizacoes  <-  Video  
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_video_ins() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    UPDATE Canal c
       SET qtd_videos        = c.qtd_videos + d.n,
           qtd_visualizacoes = c.qtd_visualizacoes + d.vis
      FROM (SELECT id_canal, count(*)::int AS n, sum(visu_total)::bigint AS vis
              FROM novas GROUP BY id_canal) d
     WHERE c.id_canal = d.id_canal;
    RETURN NULL;
END $$;

CREATE OR REPLACE FUNCTION trg_video_del() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    UPDATE Canal c
       SET qtd_videos        = c.qtd_videos - d.n,
           qtd_visualizacoes = c.qtd_visualizacoes - d.vis
      FROM (SELECT id_canal, count(*)::int AS n, sum(visu_total)::bigint AS vis
              FROM antigas GROUP BY id_canal) d
     WHERE c.id_canal = d.id_canal;
    RETURN NULL;
END $$;

CREATE OR REPLACE FUNCTION trg_video_upd() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.id_canal = NEW.id_canal THEN
        UPDATE Canal SET qtd_visualizacoes = qtd_visualizacoes + (NEW.visu_total - OLD.visu_total)
         WHERE id_canal = NEW.id_canal;
    ELSE
        UPDATE Canal SET qtd_videos = qtd_videos - 1,
                         qtd_visualizacoes = qtd_visualizacoes - OLD.visu_total
         WHERE id_canal = OLD.id_canal;
        UPDATE Canal SET qtd_videos = qtd_videos + 1,
                         qtd_visualizacoes = qtd_visualizacoes + NEW.visu_total
         WHERE id_canal = NEW.id_canal;
    END IF;
    RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_video_ai ON Video;
DROP TRIGGER IF EXISTS trg_video_ad ON Video;
DROP TRIGGER IF EXISTS trg_video_au ON Video;
CREATE TRIGGER trg_video_ai AFTER INSERT ON Video
    REFERENCING NEW TABLE AS novas   FOR EACH STATEMENT EXECUTE FUNCTION trg_video_ins();
CREATE TRIGGER trg_video_ad AFTER DELETE ON Video
    REFERENCING OLD TABLE AS antigas FOR EACH STATEMENT EXECUTE FUNCTION trg_video_del();
CREATE TRIGGER trg_video_au AFTER UPDATE OF visu_total, id_canal ON Video
    FOR EACH ROW
    WHEN (OLD.visu_total IS DISTINCT FROM NEW.visu_total OR OLD.id_canal IS DISTINCT FROM NEW.id_canal)
    EXECUTE FUNCTION trg_video_upd();

-- ---------------------------------------------------------------------
-- T3. Todo canal nasce com os 5 níveis de membro             
--     Valores/gif padrão; o streamer ajusta depois via UPDATE.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_canal_niveis() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO NivelCanal (id_canal, nivel, valor, gif)
    SELECT c.id_canal, g.n,
           (ARRAY[4.99, 9.99, 19.99, 49.99, 99.99])[g.n],
           '/gifs/padrao/nivel_' || g.n || '.gif'
      FROM novas c CROSS JOIN generate_series(1, 5) AS g(n);
    RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_canal_ai ON Canal;
CREATE TRIGGER trg_canal_ai AFTER INSERT ON Canal
    REFERENCING NEW TABLE AS novas FOR EACH STATEMENT EXECUTE FUNCTION trg_canal_niveis();

-- ---------------------------------------------------------------------
-- T12. Exatamente cinco níveis por canal                       
--      O T3 cria os 5 níveis, mas nada impedia apagar um deles. Aqui:
--        * "no máximo 5": UNIQUE(id_canal, nivel) + CHECK 1..5 (create_constraints.sql)
--        * "no mínimo 5": este CONSTRAINT TRIGGER, verificado no COMMIT
--          (se o canal inteiro for apagado, ele não reclama).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_canal_exige_5_niveis() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_id bigint; v_n int;
BEGIN
    IF TG_TABLE_NAME = 'canal' THEN v_id := NEW.id_canal; ELSE v_id := OLD.id_canal; END IF;

    IF EXISTS (SELECT 1 FROM Canal WHERE id_canal = v_id) THEN
        SELECT count(*) INTO v_n FROM NivelCanal WHERE id_canal = v_id;
        IF v_n <> 5 THEN
            RAISE EXCEPTION 'Canal % deve ter exatamente 5 níveis de membro (tem %)', v_id, v_n
                  USING ERRCODE = 'integrity_constraint_violation';
        END IF;
    END IF;
    RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_canal_5niveis_i ON Canal;
DROP TRIGGER IF EXISTS trg_nivel_5niveis_d ON NivelCanal;
CREATE CONSTRAINT TRIGGER trg_canal_5niveis_i AFTER INSERT ON Canal
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION trg_canal_exige_5_niveis();
CREATE CONSTRAINT TRIGGER trg_nivel_5niveis_d AFTER DELETE OR UPDATE OF id_canal, nivel ON NivelCanal
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION trg_canal_exige_5_niveis();

-- ---------------------------------------------------------------------
-- T4. Vídeo não pode ser anterior ao início do canal        
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_video_bi() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_inicio date;
BEGIN
    SELECT c.data INTO v_inicio FROM Canal c WHERE c.id_canal = NEW.id_canal;
    IF v_inicio IS NOT NULL AND NEW.dataH::date < v_inicio THEN
        RAISE EXCEPTION 'Vídeo (%) anterior ao início do canal % (%)', NEW.dataH, NEW.id_canal, v_inicio
              USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_video_bi ON Video;
CREATE TRIGGER trg_video_bi BEFORE INSERT OR UPDATE OF dataH, id_canal ON Video
    FOR EACH ROW EXECUTE FUNCTION trg_video_bi();

-- ---------------------------------------------------------------------
-- T5. Participa: apenas convidados (o dono do canal já é "autor")
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_participa_bi() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM Video v JOIN Canal c ON c.id_canal = v.id_canal
                WHERE v.id_video = NEW.id_video AND c.nick_streamer = NEW.nick_streamer) THEN
        RAISE EXCEPTION 'O dono do canal não deve ser registrado como convidado (video %, streamer %)',
              NEW.id_video, NEW.nick_streamer USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_participa_bi ON Participa;
CREATE TRIGGER trg_participa_bi BEFORE INSERT OR UPDATE OF id_video, nick_streamer ON Participa
    FOR EACH ROW EXECUTE FUNCTION trg_participa_bi();

-- ---------------------------------------------------------------------
-- T6. Inscrição                                              
--     * regra: o dono do canal não pode
--       ser membro do próprio canal
--     * ajuste: o nível escolhido tem que pertencer AO MESMO canal da
--       inscrição (não há FK composta garantindo isso)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_inscricao_bi() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM Canal WHERE id_canal = NEW.id_canal AND nick_streamer = NEW.nick_membro) THEN
        RAISE EXCEPTION 'O dono do canal % não pode ser membro dele mesmo', NEW.id_canal
              USING ERRCODE = 'check_violation';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM NivelCanal
                    WHERE id_nivel_canal = NEW.id_nivel_canal AND id_canal = NEW.id_canal) THEN
        RAISE EXCEPTION 'O nível % não pertence ao canal %', NEW.id_nivel_canal, NEW.id_canal
              USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_inscricao_bi ON Inscricao;
CREATE TRIGGER trg_inscricao_bi BEFORE INSERT OR UPDATE OF id_canal, nick_membro, id_nivel_canal ON Inscricao
    FOR EACH ROW EXECUTE FUNCTION trg_inscricao_bi();

-- ---------------------------------------------------------------------
-- T7. Comentário: sequencial por vídeo + data não anterior ao vídeo
--     MAX(seq)+1 com advisory lock por vídeo, que evita números repetidos em concorrência.
--     Numeração por VÍDEO; satisfaz também a UNIQUE (id_video, nick_usuario, seq) existente.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_comentario_bi() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_data timestamp;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF NEW.id_video <> OLD.id_video OR NEW.seq <> OLD.seq THEN
            RAISE EXCEPTION 'id_video e seq do comentário são imutáveis' USING ERRCODE = 'check_violation';
        END IF;
        RETURN NEW;
    END IF;

    SELECT v.dataH INTO v_data FROM Video v WHERE v.id_video = NEW.id_video;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Vídeo % inexistente', NEW.id_video USING ERRCODE = 'foreign_key_violation';
    END IF;

    IF NEW.seq IS NULL THEN
        PERFORM pg_advisory_xact_lock(hashtext('comentario_seq|' || NEW.id_video));
        SELECT COALESCE(MAX(c.seq), 0) + 1 INTO NEW.seq
          FROM Comentario c WHERE c.id_video = NEW.id_video;
    END IF;

    IF NEW.dataH < v_data THEN
        RAISE EXCEPTION 'Comentário (%) anterior à postagem do vídeo (%)', NEW.dataH, v_data
              USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_comentario_bi ON Comentario;
DROP TRIGGER IF EXISTS trg_comentario_bu ON Comentario;
CREATE TRIGGER trg_comentario_bi BEFORE INSERT ON Comentario
    FOR EACH ROW EXECUTE FUNCTION trg_comentario_bi();
CREATE TRIGGER trg_comentario_bu BEFORE UPDATE OF id_video, seq ON Comentario
    FOR EACH ROW EXECUTE FUNCTION trg_comentario_bi();

-- ---------------------------------------------------------------------
-- T8. Doação: seq_pg por comentário                         
--     Mesma técnica do T7 (sem coluna contadora extra).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_doacao_bi() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.seq_pg IS NULL THEN
        PERFORM pg_advisory_xact_lock(hashtext('doacao_seq|' || NEW.id_comentario));
        SELECT COALESCE(MAX(d.seq_pg), 0) + 1 INTO NEW.seq_pg
          FROM Doacao d WHERE d.id_comentario = NEW.id_comentario;
    END IF;
    RETURN NEW;   -- comentário inexistente é barrado pela FK fk_doacao_comentario
END $$;

DROP TRIGGER IF EXISTS trg_doacao_bi ON Doacao;
CREATE TRIGGER trg_doacao_bi BEFORE INSERT ON Doacao
    FOR EACH ROW EXECUTE FUNCTION trg_doacao_bi();

-- Doação via mecanismo da plataforma: nº sequencial por comentário (a
-- plataforma e o usuário já ficam fixos pelo comentário -> vídeo -> canal).
CREATE OR REPLACE FUNCTION trg_doacao_plat_bi() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_com bigint;
BEGIN
    IF NEW.seq_plataforma IS NULL THEN
        SELECT d.id_comentario INTO v_com FROM Doacao d WHERE d.id_doacao = NEW.id_doacao;
        IF v_com IS NULL THEN RETURN NEW; END IF;   -- a FK reclama da doação inexistente
        PERFORM pg_advisory_xact_lock(hashtext('mecplat_seq|' || v_com));
        SELECT COALESCE(MAX(m.seq_plataforma), 0) + 1 INTO NEW.seq_plataforma
          FROM MecanismoPlat m JOIN Doacao d ON d.id_doacao = m.id_doacao
         WHERE d.id_comentario = v_com;
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_doacao_plat_bi ON MecanismoPlat;
CREATE TRIGGER trg_doacao_plat_bi BEFORE INSERT ON MecanismoPlat
    FOR EACH ROW EXECUTE FUNCTION trg_doacao_plat_bi();

-- ---------------------------------------------------------------------
-- T13. Exclusividade: uma doação em NO MÁXIMO uma forma de pagamento 
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_doacao_forma_exclusiva() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    PERFORM pg_advisory_xact_lock(hashtext('doacao_forma|' || NEW.id_doacao));
    IF (TG_TABLE_NAME <> 'bitcoin'       AND EXISTS (SELECT 1 FROM BitCoin       WHERE id_doacao = NEW.id_doacao))
    OR (TG_TABLE_NAME <> 'paypal'        AND EXISTS (SELECT 1 FROM PayPal        WHERE id_doacao = NEW.id_doacao))
    OR (TG_TABLE_NAME <> 'cartaocredito' AND EXISTS (SELECT 1 FROM CartaoCredito WHERE id_doacao = NEW.id_doacao))
    OR (TG_TABLE_NAME <> 'mecanismoplat' AND EXISTS (SELECT 1 FROM MecanismoPlat WHERE id_doacao = NEW.id_doacao))
    THEN
        RAISE EXCEPTION 'Doação % já está registrada em outra forma de pagamento', NEW.id_doacao
              USING ERRCODE = 'integrity_constraint_violation';
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_bitcoin_excl  ON BitCoin;
DROP TRIGGER IF EXISTS trg_paypal_excl   ON PayPal;
DROP TRIGGER IF EXISTS trg_cartao_excl   ON CartaoCredito;
DROP TRIGGER IF EXISTS trg_mecplat_excl  ON MecanismoPlat;
CREATE TRIGGER trg_bitcoin_excl BEFORE INSERT OR UPDATE OF id_doacao ON BitCoin
    FOR EACH ROW EXECUTE FUNCTION trg_doacao_forma_exclusiva();
CREATE TRIGGER trg_paypal_excl  BEFORE INSERT OR UPDATE OF id_doacao ON PayPal
    FOR EACH ROW EXECUTE FUNCTION trg_doacao_forma_exclusiva();
CREATE TRIGGER trg_cartao_excl  BEFORE INSERT OR UPDATE OF id_doacao ON CartaoCredito
    FOR EACH ROW EXECUTE FUNCTION trg_doacao_forma_exclusiva();
CREATE TRIGGER trg_mecplat_excl BEFORE INSERT OR UPDATE OF id_doacao ON MecanismoPlat
    FOR EACH ROW EXECUTE FUNCTION trg_doacao_forma_exclusiva();

-- ---------------------------------------------------------------------
-- T9a. Totalidade: toda doação tem exatamente 1 forma de pagamento
--      Verificado no COMMIT (DEFERRABLE): a doação e sua subtabela devem ser
--      inseridas na MESMA transação. Também dispara quando uma linha de
--      subtabela é apagada, para não deixar a doação "órfã" de forma.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_doacao_exige_subtipo() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_id bigint; v_n int;
BEGIN
    IF TG_TABLE_NAME = 'doacao' THEN v_id := NEW.id_doacao; ELSE v_id := OLD.id_doacao; END IF;

    IF NOT EXISTS (SELECT 1 FROM Doacao WHERE id_doacao = v_id) THEN
        RETURN NULL;                       -- removida na mesma transação
    END IF;

    v_n := (SELECT count(*) FROM BitCoin       WHERE id_doacao = v_id)
         + (SELECT count(*) FROM PayPal        WHERE id_doacao = v_id)
         + (SELECT count(*) FROM CartaoCredito WHERE id_doacao = v_id)
         + (SELECT count(*) FROM MecanismoPlat WHERE id_doacao = v_id);

    IF v_n <> 1 THEN
        RAISE EXCEPTION 'Doação % deve ter exatamente 1 forma de pagamento (tem %)', v_id, v_n
              USING ERRCODE = 'integrity_constraint_violation';
    END IF;
    RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_doacao_subtipo      ON Doacao;
DROP TRIGGER IF EXISTS trg_bitcoin_subtipo_d   ON BitCoin;
DROP TRIGGER IF EXISTS trg_paypal_subtipo_d    ON PayPal;
DROP TRIGGER IF EXISTS trg_cartao_subtipo_d    ON CartaoCredito;
DROP TRIGGER IF EXISTS trg_mecplat_subtipo_d   ON MecanismoPlat;
CREATE CONSTRAINT TRIGGER trg_doacao_subtipo AFTER INSERT ON Doacao
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION trg_doacao_exige_subtipo();
CREATE CONSTRAINT TRIGGER trg_bitcoin_subtipo_d AFTER DELETE ON BitCoin
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION trg_doacao_exige_subtipo();
CREATE CONSTRAINT TRIGGER trg_paypal_subtipo_d AFTER DELETE ON PayPal
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION trg_doacao_exige_subtipo();
CREATE CONSTRAINT TRIGGER trg_cartao_subtipo_d AFTER DELETE ON CartaoCredito
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION trg_doacao_exige_subtipo();
CREATE CONSTRAINT TRIGGER trg_mecplat_subtipo_d AFTER DELETE ON MecanismoPlat
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION trg_doacao_exige_subtipo();

-- ---------------------------------------------------------------------
-- T9b. Toda empresa tem >= 1 país de origem (+ id nacional)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_empresa_exige_pais() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_id bigint;
BEGIN
    IF TG_TABLE_NAME = 'empresa' THEN v_id := NEW.nro; ELSE v_id := OLD.nro_empresa; END IF;

    IF EXISTS (SELECT 1 FROM Empresa WHERE nro = v_id)
       AND NOT EXISTS (SELECT 1 FROM EmpresaPais WHERE nro_empresa = v_id) THEN
        RAISE EXCEPTION 'Empresa % precisa de ao menos um país de origem/identificador nacional', v_id
              USING ERRCODE = 'integrity_constraint_violation';
    END IF;
    RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_empresa_pais_i ON Empresa;
DROP TRIGGER IF EXISTS trg_empresa_pais_d ON EmpresaPais;
CREATE CONSTRAINT TRIGGER trg_empresa_pais_i AFTER INSERT ON Empresa
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION trg_empresa_exige_pais();
CREATE CONSTRAINT TRIGGER trg_empresa_pais_d AFTER DELETE ON EmpresaPais
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION trg_empresa_exige_pais();

-- ---------------------------------------------------------------------
-- T10. Dono de canal e participante de vídeo exigem passaporte
--      Hoje Canal.nick_streamer e Participa.nick_streamer só referenciam
--      Usuario, então qualquer usuário comum poderia ser "streamer".
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_exige_passaporte() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM StreamerPais WHERE nick_streamer = NEW.nick_streamer) THEN
        RAISE EXCEPTION 'Usuário "%" não tem passaporte em StreamerPais: não pode constar em % como streamer',
              NEW.nick_streamer, TG_TABLE_NAME
              USING ERRCODE = 'integrity_constraint_violation';
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_canal_passaporte    ON Canal;
DROP TRIGGER IF EXISTS trg_participa_passaporte ON Participa;
CREATE TRIGGER trg_canal_passaporte BEFORE INSERT OR UPDATE OF nick_streamer ON Canal
    FOR EACH ROW EXECUTE FUNCTION trg_exige_passaporte();
CREATE TRIGGER trg_participa_passaporte BEFORE INSERT OR UPDATE OF nick_streamer ON Participa
    FOR EACH ROW EXECUTE FUNCTION trg_exige_passaporte();

-- ---------------------------------------------------------------------
-- T11. Não apagar o último passaporte de quem tem canal         
--      Protege também quem é convidado em algum vídeo (mesma regra do T10).
--      Cobre DELETE e o UPDATE que "move" o passaporte para outro nick.
--      Se o próprio Usuario está sendo apagado (DELETE em cascata), o
--      trigger deixa passar: nesse caso a FK RESTRICT de Canal já barra
--      quem tem canal, e Participa é apagada em cascata.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_passaporte_ultimo() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM Usuario WHERE nick = OLD.nick_streamer)
       AND ( EXISTS (SELECT 1 FROM Canal    WHERE nick_streamer = OLD.nick_streamer)
          OR EXISTS (SELECT 1 FROM Participa WHERE nick_streamer = OLD.nick_streamer) )
       AND NOT EXISTS (SELECT 1 FROM StreamerPais
                        WHERE nick_streamer = OLD.nick_streamer AND ddi_pais <> OLD.ddi_pais) THEN
        RAISE EXCEPTION 'Não é possível remover o último passaporte de "%": ele é dono de canal ou participante de vídeo',
              OLD.nick_streamer USING ERRCODE = 'integrity_constraint_violation';
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_passaporte_ultimo ON StreamerPais;
CREATE TRIGGER trg_passaporte_ultimo BEFORE DELETE OR UPDATE OF nick_streamer ON StreamerPais
    FOR EACH ROW EXECUTE FUNCTION trg_passaporte_ultimo();