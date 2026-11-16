-- ---------------------------------------------------------------------
-- Triggers (parte 1), visões e procedure de atualização (parte 2) e
-- functions de consulta (parte 3).
-- As visões materializadas nascem vazias aqui; o 03_dados.sql as atualiza
-- no final com CALL sp_atualizar_visoes().
-- ---------------------------------------------------------------------

-- #####################################################################
-- PARTE 1 - TRIGGERS (T01 a T11)
-- #####################################################################

-- ---------------------------------------------------------------------
-- T01: dono de canal e convidado de vídeo precisam ter passaporte
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_t01_passaporte() RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM StreamerPais WHERE nick_streamer = NEW.nick_streamer
    ) THEN
        RAISE EXCEPTION 'T01: % não possui passaporte cadastrado em StreamerPais', NEW.nick_streamer;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_t01_passaporte_canal
    BEFORE INSERT ON Canal
    FOR EACH ROW EXECUTE FUNCTION fn_t01_passaporte();

CREATE TRIGGER trg_t01_passaporte_participa
    BEFORE INSERT ON Participa
    FOR EACH ROW EXECUTE FUNCTION fn_t01_passaporte();


-- ---------------------------------------------------------------------
-- T02: não apagar o último passaporte de quem tem canal ou participação
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_t02_ultimo_passaporte() RETURNS TRIGGER AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM StreamerPais
                WHERE nick_streamer = OLD.nick_streamer AND ddi_pais <> OLD.ddi_pais) THEN
        RETURN OLD;
    END IF;
    IF EXISTS (SELECT 1 FROM Canal WHERE nick_streamer = OLD.nick_streamer)
       OR EXISTS (SELECT 1 FROM Participa WHERE nick_streamer = OLD.nick_streamer) THEN
        RAISE EXCEPTION 'T02: não é possível remover o último passaporte de %, pois o usuário possui canal ou participação', OLD.nick_streamer;
    END IF;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_t02_ultimo_passaporte
    BEFORE DELETE ON StreamerPais
    FOR EACH ROW EXECUTE FUNCTION fn_t02_ultimo_passaporte();


-- ---------------------------------------------------------------------
-- T03: uma doação aparece em no máximo um meio de pagamento (na inserção)
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_t03_forma_unica() RETURNS TRIGGER AS $$
BEGIN
    IF (TG_TABLE_NAME <> 'cartaocredito' AND EXISTS (SELECT 1 FROM CartaoCredito WHERE id_comentario = NEW.id_comentario))
    OR (TG_TABLE_NAME <> 'bitcoin'       AND EXISTS (SELECT 1 FROM BitCoin       WHERE id_comentario = NEW.id_comentario))
    OR (TG_TABLE_NAME <> 'paypal'        AND EXISTS (SELECT 1 FROM PayPal        WHERE id_comentario = NEW.id_comentario))
    OR (TG_TABLE_NAME <> 'mecanismoplat' AND EXISTS (SELECT 1 FROM MecanismoPlat WHERE id_comentario = NEW.id_comentario))
    THEN
        RAISE EXCEPTION 'T03: a doação % já possui outra forma de pagamento', NEW.id_comentario;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_t03_forma_unica_cartao    BEFORE INSERT ON CartaoCredito FOR EACH ROW EXECUTE FUNCTION fn_t03_forma_unica();
CREATE TRIGGER trg_t03_forma_unica_bitcoin   BEFORE INSERT ON BitCoin       FOR EACH ROW EXECUTE FUNCTION fn_t03_forma_unica();
CREATE TRIGGER trg_t03_forma_unica_paypal    BEFORE INSERT ON PayPal        FOR EACH ROW EXECUTE FUNCTION fn_t03_forma_unica();
CREATE TRIGGER trg_t03_forma_unica_mecanismo BEFORE INSERT ON MecanismoPlat FOR EACH ROW EXECUTE FUNCTION fn_t03_forma_unica();


-- ---------------------------------------------------------------------
-- T04: toda doação tem exatamente uma forma de pagamento (deferido, no COMMIT)
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_t04_chk_forma_completa(p_id_comentario INTEGER) RETURNS VOID AS $$
DECLARE
    v_qtd INTEGER;
BEGIN
    IF EXISTS (SELECT 1 FROM Doacao WHERE id_comentario = p_id_comentario) THEN
        SELECT (SELECT COUNT(*) FROM CartaoCredito WHERE id_comentario = p_id_comentario)
             + (SELECT COUNT(*) FROM BitCoin       WHERE id_comentario = p_id_comentario)
             + (SELECT COUNT(*) FROM PayPal        WHERE id_comentario = p_id_comentario)
             + (SELECT COUNT(*) FROM MecanismoPlat WHERE id_comentario = p_id_comentario)
          INTO v_qtd;
        IF v_qtd <> 1 THEN
            RAISE EXCEPTION 'T04: a doação % deve ter exatamente uma forma de pagamento (tem %)', p_id_comentario, v_qtd;
        END IF;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION fn_t04_forma_completa() RETURNS TRIGGER AS $$
BEGIN
    IF TG_TABLE_NAME = 'doacao' THEN
        PERFORM fn_t04_chk_forma_completa(NEW.id_comentario);
    ELSE
        PERFORM fn_t04_chk_forma_completa(OLD.id_comentario);
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER trg_t04_forma_completa_doacao
    AFTER INSERT ON Doacao
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION fn_t04_forma_completa();

CREATE CONSTRAINT TRIGGER trg_t04_forma_completa_cartao
    AFTER DELETE ON CartaoCredito
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION fn_t04_forma_completa();

CREATE CONSTRAINT TRIGGER trg_t04_forma_completa_bitcoin
    AFTER DELETE ON BitCoin
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION fn_t04_forma_completa();

CREATE CONSTRAINT TRIGGER trg_t04_forma_completa_paypal
    AFTER DELETE ON PayPal
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION fn_t04_forma_completa();

CREATE CONSTRAINT TRIGGER trg_t04_forma_completa_mecanismo
    AFTER DELETE ON MecanismoPlat
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION fn_t04_forma_completa();


-- ---------------------------------------------------------------------
-- T05: todo canal tem exatamente cinco níveis (deferido, no COMMIT)
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_t05_cinco_niveis() RETURNS TRIGGER AS $$
DECLARE
    v_canal INTEGER;
    v_qtd   INTEGER;
BEGIN
    v_canal := COALESCE(NEW.id_canal, OLD.id_canal);
    IF NOT EXISTS (SELECT 1 FROM Canal WHERE id_canal = v_canal) THEN
        RETURN NULL;
    END IF;
    SELECT COUNT(*) INTO v_qtd FROM NivelCanal WHERE id_canal = v_canal;
    IF v_qtd <> 5 THEN
        RAISE EXCEPTION 'T05: o canal % deve ter exatamente 5 níveis (tem %)', v_canal, v_qtd;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER trg_t05_cinco_niveis
    AFTER INSERT OR DELETE ON NivelCanal
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION fn_t05_cinco_niveis();


-- ---------------------------------------------------------------------
-- T06: converte a doação para USD na gravação
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_t06_conversao_doacao() RETURNS TRIGGER AS $$
DECLARE
    v_fator NUMERIC(12,6);
BEGIN
    SELECT fator_conver INTO v_fator FROM Conversao WHERE moeda = NEW.moeda;
    NEW.valor := ROUND(NEW.valor_original * v_fator, 2);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_t06_conversao_doacao
    BEFORE INSERT ON Doacao
    FOR EACH ROW EXECUTE FUNCTION fn_t06_conversao_doacao();


-- ---------------------------------------------------------------------
-- T07: vídeo não pode ser anterior ao início do canal
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_t07_video_inicio_canal() RETURNS TRIGGER AS $$
DECLARE
    v_inicio DATE;
BEGIN
    SELECT data_inicio INTO v_inicio FROM Canal WHERE id_canal = NEW.id_canal;
    IF NEW.dataH::date < v_inicio THEN
        RAISE EXCEPTION 'T07: o vídeo (%) é anterior ao início do canal % (%)', NEW.dataH, NEW.id_canal, v_inicio;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_t07_video_inicio_canal
    BEFORE INSERT ON Video
    FOR EACH ROW EXECUTE FUNCTION fn_t07_video_inicio_canal();


-- ---------------------------------------------------------------------
-- T08: dono do canal não pode ser convidado do próprio vídeo
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_t08_convidado_nao_dono() RETURNS TRIGGER AS $$
DECLARE
    v_dono VARCHAR;
BEGIN
    SELECT c.nick_streamer INTO v_dono
      FROM Video v JOIN Canal c ON c.id_canal = v.id_canal
     WHERE v.id_video = NEW.id_video;
    IF v_dono = NEW.nick_streamer THEN
        RAISE EXCEPTION 'T08: % é dono do canal e não pode ser convidado do vídeo %', NEW.nick_streamer, NEW.id_video;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_t08_convidado_nao_dono
    BEFORE INSERT ON Participa
    FOR EACH ROW EXECUTE FUNCTION fn_t08_convidado_nao_dono();


-- ---------------------------------------------------------------------
-- T09: dono do canal não pode ser membro dele
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_t09_membro_nao_dono() RETURNS TRIGGER AS $$
DECLARE
    v_dono VARCHAR;
BEGIN
    SELECT nick_streamer INTO v_dono FROM Canal WHERE id_canal = NEW.id_canal;
    IF v_dono = NEW.nick_membro THEN
        RAISE EXCEPTION 'T09: % é dono do canal % e não pode ser membro dele', NEW.nick_membro, NEW.id_canal;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_t09_membro_nao_dono
    BEFORE INSERT ON Inscricao
    FOR EACH ROW EXECUTE FUNCTION fn_t09_membro_nao_dono();


-- ---------------------------------------------------------------------
-- T10: comentário não pode ser anterior à postagem do vídeo
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_t10_comentario_apos_postagem() RETURNS TRIGGER AS $$
DECLARE
    v_postagem TIMESTAMP;
BEGIN
    SELECT dataH INTO v_postagem FROM Video WHERE id_video = NEW.id_video;
    IF NEW.dataH < v_postagem THEN
        RAISE EXCEPTION 'T10: o comentário (%) é anterior à postagem do vídeo (%)', NEW.dataH, v_postagem;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_t10_comentario_apos_postagem
    BEFORE INSERT ON Comentario
    FOR EACH ROW EXECUTE FUNCTION fn_t10_comentario_apos_postagem();


-- ---------------------------------------------------------------------
-- T11: toda empresa tem ao menos um país de origem (deferido, no COMMIT)
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_t11_chk_empresa_pais(p_nro INTEGER) RETURNS VOID AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM Empresa WHERE nro = p_nro)
       AND NOT EXISTS (SELECT 1 FROM EmpresaPais WHERE nro_empresa = p_nro) THEN
        RAISE EXCEPTION 'T11: a empresa % deve ter ao menos um país de origem', p_nro;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION fn_t11_empresa_com_pais() RETURNS TRIGGER AS $$
BEGIN
    IF TG_TABLE_NAME = 'empresa' THEN
        PERFORM fn_t11_chk_empresa_pais(NEW.nro);
    ELSE
        PERFORM fn_t11_chk_empresa_pais(OLD.nro_empresa);
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER trg_t11_empresa_com_pais_empresa
    AFTER INSERT ON Empresa
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION fn_t11_empresa_com_pais();

CREATE CONSTRAINT TRIGGER trg_t11_empresa_com_pais_vinculo
    AFTER DELETE ON EmpresaPais
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION fn_t11_empresa_com_pais();


-- #####################################################################
-- PARTE 2 - VISÕES (5) E PROCEDURE DE ATUALIZAÇÃO
-- #####################################################################

-- Resumo (até 5 visões):
--   V1 vw_comentarios_video  MATERIALIZADA  consultas 2 e 3
--   V2 vw_doacao_canal       MATERIALIZADA  consultas 4, 7, 10 e 11
--   V3 vw_patrocinio_canal   virtual        consultas 8 e 11
--   V4 vw_membros_canal      virtual        consultas 9 e 11
--   V5 vw_receita_canal      virtual        consulta 11
-- Nenhuma materializada tem índice próprio: cerca de 1.000 linhas cada, e a
-- vaga de índice rende mais numa tabela base (idx_canal_streamer, no DDL).
-- Atualização: CALL sp_atualizar_visoes(); após qualquer carga nova.

-- ---------------------------------------------------------------------
-- V1 (materializada): comentários online, offline e total por vídeo.
-- LEFT JOIN: vídeo sem comentário aparece com zeros. Sem isso, a média de
-- interações por vídeo (consulta 3) sairia inflada.
-- Materializada porque varre Video x Comentario inteira (a maior junção do
-- banco) e a defasagem é aceitável entre cargas.
-- ---------------------------------------------------------------------
CREATE MATERIALIZED VIEW vw_comentarios_video AS
SELECT v.id_video,
       v.id_canal,
       v.titulo,
       v.dataH,
       COUNT(c.id_comentario) FILTER (WHERE c.coment_on)     AS qtd_online,
       COUNT(c.id_comentario) FILTER (WHERE NOT c.coment_on) AS qtd_offline,
       COUNT(c.id_comentario)                                AS qtd_total
  FROM Video v
  LEFT JOIN Comentario c ON c.id_video = v.id_video
 GROUP BY v.id_video, v.id_canal, v.titulo, v.dataH;


-- ---------------------------------------------------------------------
-- V2 (materializada): doações por canal, em USD.
-- Premissa: doação com status 'recusado' não gerou dinheiro e fica de fora.
-- INNER JOIN: só aparecem canais que já receberam doação (consulta 7).
-- nro_plataforma vai na view para o filtro da consulta 4, sem junção extra.
-- Materializada porque faz Doacao -> Comentario -> Video -> Canal.
-- ---------------------------------------------------------------------
CREATE MATERIALIZED VIEW vw_doacao_canal AS
SELECT ca.id_canal,
       ca.nro_plataforma,
       COUNT(*)                AS qtd_doacoes,
       SUM(d.valor)            AS soma_usd,
       ROUND(AVG(d.valor), 2)  AS media_usd
  FROM Doacao d
  JOIN Comentario co ON co.id_comentario = d.id_comentario
  JOIN Video v       ON v.id_video       = co.id_video
  JOIN Canal ca      ON ca.id_canal      = v.id_canal
 WHERE d.status <> 'recusado'
 GROUP BY ca.id_canal, ca.nro_plataforma;

-- Nenhuma visão materializada tem índice próprio: cada uma tem cerca de
-- 1.000 linhas, e a 5ª vaga de índice rende mais numa tabela base
-- (idx_canal_streamer, no 01_ddl.sql).


-- ---------------------------------------------------------------------
-- V3 (virtual): patrocínio vigente somado por canal.
-- Virtual porque a agregação é barata e o dado precisa estar sempre atual.
-- ---------------------------------------------------------------------
CREATE VIEW vw_patrocinio_canal AS
SELECT id_canal,
       COUNT(*)   AS qtd_patrocinadores,
       SUM(valor) AS soma_patrocinio
  FROM Patrocinio
 GROUP BY id_canal;


-- ---------------------------------------------------------------------
-- V4 (virtual): aporte mensal de membros por canal.
-- O valor vem do nível do membro (Inscricao -> NivelCanal).
-- ---------------------------------------------------------------------
CREATE VIEW vw_membros_canal AS
SELECT i.id_canal,
       COUNT(*)     AS qtd_membros,
       SUM(n.valor) AS soma_mensal_usd
  FROM Inscricao i
  JOIN NivelCanal n ON n.id_canal = i.id_canal
                   AND n.nivel    = i.nivel
 GROUP BY i.id_canal;


-- ---------------------------------------------------------------------
-- V5 (virtual): receita total por canal (patrocínio + membros + doações).
-- Cada fonte já chega agregada em uma linha por canal (V3, V4, V2), então
-- a junção não multiplica linhas e as somas saem corretas. Juntar as
-- tabelas cruas de uma vez inflaria cada fonte pelas outras.
-- LEFT JOIN + COALESCE: canal sem alguma das fontes entra com zero.
-- ---------------------------------------------------------------------
CREATE VIEW vw_receita_canal AS
SELECT c.id_canal,
       c.nome,
       c.nro_plataforma,
       COALESCE(p.soma_patrocinio,  0) AS patrocinio,
       COALESCE(m.soma_mensal_usd,  0) AS membros,
       COALESCE(d.soma_usd,         0) AS doacoes,
       COALESCE(p.soma_patrocinio,  0)
     + COALESCE(m.soma_mensal_usd,  0)
     + COALESCE(d.soma_usd,         0) AS total
  FROM Canal c
  LEFT JOIN vw_patrocinio_canal p ON p.id_canal = c.id_canal
  LEFT JOIN vw_membros_canal    m ON m.id_canal = c.id_canal
  LEFT JOIN vw_doacao_canal     d ON d.id_canal = c.id_canal;


-- ---------------------------------------------------------------------
-- Atualização das materializadas: CALL sp_atualizar_visoes();
-- Chamar depois de qualquer carga nova, inclusive depois do 04_testes.sql,
-- que insere comentários e doações. O refresh é o completo (sem
-- CONCURRENTLY), pois as visões não têm índice único.
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_atualizar_visoes()
LANGUAGE plpgsql AS $$
BEGIN
    REFRESH MATERIALIZED VIEW vw_comentarios_video;
    REFRESH MATERIALIZED VIEW vw_doacao_canal;
END;
$$;


-- ---------------------------------------------------------------------
-- Conferências (cada par deve dar o mesmo valor)
-- ---------------------------------------------------------------------
-- SELECT SUM(qtd_total) FROM vw_comentarios_video;
-- SELECT COUNT(*)       FROM Comentario;
--
-- SELECT SUM(soma_usd) FROM vw_doacao_canal;
-- SELECT SUM(valor)    FROM Doacao WHERE status <> 'recusado';
--
-- SELECT SUM(total) FROM vw_receita_canal;
-- SELECT (SELECT COALESCE(SUM(valor),0) FROM Patrocinio)
--      + (SELECT COALESCE(SUM(soma_mensal_usd),0) FROM vw_membros_canal)
--      + (SELECT COALESCE(SUM(soma_usd),0) FROM vw_doacao_canal);


-- #####################################################################
-- PARTE 3 - CONSULTAS (12 functions parametrizadas)
-- #####################################################################

-- Convenções:
--   * Streamer = dono do canal (Canal.nick_streamer). Convidados (Participa)
--     não entram nas contagens.
--   * Parâmetro de filtro: DEFAULT NULL = sem filtro.
--   * Parâmetro k: nas consultas 8 a 11 o padrão é 10 e k nulo ou <= 0 dá
--     erro; na 12, k nulo devolve todas as plataformas (k <= 0 dá erro).
--   * Functions STABLE: só leem dados. Valores em USD; doação recusada não conta.
--   * Colunas sempre com alias: os nomes do RETURNS TABLE viram variáveis em
--     PL/pgSQL e causariam "column reference is ambiguous". Por isso o
--     ORDER BY usa posição ou coluna qualificada.
--   * Q2, Q3, Q4, Q7, Q10 e Q11 leem materializadas: CALL sp_atualizar_visoes().

-- ---------------------------------------------------------------------
-- Q1: streamers com mais vídeos publicados (quantidade e soma de visualizações)
-- Filtro opcional: plataforma (Plataforma.nro)
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_q01_streamers_mais_videos(
    p_plataforma INTEGER DEFAULT NULL
)
RETURNS TABLE (
    nick_streamer   VARCHAR,
    qtd_videos      BIGINT,
    soma_visu_total BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT c.nick_streamer,
           COUNT(v.id_video),
           SUM(v.visu_total)
      FROM Canal c
      JOIN Video v ON v.id_canal = c.id_canal
     WHERE p_plataforma IS NULL OR c.nro_plataforma = p_plataforma
     GROUP BY c.nick_streamer
     ORDER BY 2 DESC, 3 DESC, 1;
END;
$$ LANGUAGE plpgsql STABLE;


-- ---------------------------------------------------------------------
-- Q2: vídeos com mais comentários (online, offline e total)
-- Filtro opcional: canal (Canal.id_canal). Lê da V1.
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_q02_videos_mais_comentados(
    p_canal INTEGER DEFAULT NULL
)
RETURNS TABLE (
    id_video    INTEGER,
    titulo      VARCHAR,
    id_canal    INTEGER,
    canal_nome  VARCHAR,
    qtd_online  BIGINT,
    qtd_offline BIGINT,
    qtd_total   BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT m.id_video, m.titulo, m.id_canal, c.nome,
           m.qtd_online, m.qtd_offline, m.qtd_total
      FROM vw_comentarios_video m
      JOIN Canal c ON c.id_canal = m.id_canal
     WHERE p_canal IS NULL OR m.id_canal = p_canal
     ORDER BY m.qtd_total DESC, m.id_video;
END;
$$ LANGUAGE plpgsql STABLE;


-- ---------------------------------------------------------------------
-- Q3: canais por total de interações (comentários online + offline) e
-- média por vídeo. Filtro opcional: streamer (nick do dono). Lê da V1.
-- LEFT JOIN: canal sem vídeo aparece com 0 (e média 0).
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_q03_canais_mais_interacoes(
    p_streamer VARCHAR DEFAULT NULL
)
RETURNS TABLE (
    id_canal         INTEGER,
    nome             VARCHAR,
    nick_streamer    VARCHAR,
    plataforma_nome  VARCHAR,
    qtd_videos       BIGINT,
    total_interacoes BIGINT,
    media_por_video  NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT c.id_canal,
           c.nome,
           c.nick_streamer,
           pl.nome,
           COUNT(m.id_video),
           COALESCE(SUM(m.qtd_total), 0)::BIGINT,
           COALESCE(ROUND(SUM(m.qtd_total)::NUMERIC
                          / NULLIF(COUNT(m.id_video), 0), 2), 0)
      FROM Canal c
      JOIN Plataforma pl ON pl.nro = c.nro_plataforma
      LEFT JOIN vw_comentarios_video m ON m.id_canal = c.id_canal
     WHERE p_streamer IS NULL OR c.nick_streamer = p_streamer
     GROUP BY c.id_canal, c.nome, c.nick_streamer, pl.nome
     ORDER BY 6 DESC, 1;
END;
$$ LANGUAGE plpgsql STABLE;


-- ---------------------------------------------------------------------
-- Q4: canais pelo valor médio das doações (por comentário = por doação,
-- pois cada comentário tem no máximo uma doação). Mostra também a
-- quantidade e o total. Filtro opcional: plataforma. Lê da V2.
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_q04_canais_media_doacao(
    p_plataforma INTEGER DEFAULT NULL
)
RETURNS TABLE (
    id_canal       INTEGER,
    nome           VARCHAR,
    nro_plataforma INTEGER,
    media_usd      NUMERIC,
    qtd_doacoes    BIGINT,
    soma_usd       NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT d.id_canal, c.nome, d.nro_plataforma,
           d.media_usd, d.qtd_doacoes, d.soma_usd
      FROM vw_doacao_canal d
      JOIN Canal c ON c.id_canal = d.id_canal
     WHERE p_plataforma IS NULL OR d.nro_plataforma = p_plataforma
     ORDER BY d.media_usd DESC, d.id_canal;
END;
$$ LANGUAGE plpgsql STABLE;


-- ---------------------------------------------------------------------
-- Q5: canais patrocinados e valor pago por empresa.
-- Filtro opcional: empresa (Empresa.nro). Lê direto de Patrocinio.
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_q05_patrocinios_por_empresa(
    p_empresa INTEGER DEFAULT NULL
)
RETURNS TABLE (
    nro_empresa  INTEGER,
    nome_empresa VARCHAR,
    id_canal     INTEGER,
    nome_canal   VARCHAR,
    plataforma_nome        VARCHAR,
    valor_usd              NUMERIC,
    total_pago_empresa_usd NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT e.nro, e.nome, c.id_canal, c.nome, pl.nome, p.valor,
           SUM(p.valor) OVER (PARTITION BY p.nro_empresa)
      FROM Patrocinio p
      JOIN Empresa    e  ON e.nro      = p.nro_empresa
      JOIN Canal      c  ON c.id_canal = p.id_canal
      JOIN Plataforma pl ON pl.nro     = c.nro_plataforma
     WHERE p_empresa IS NULL OR p.nro_empresa = p_empresa
     ORDER BY 7 DESC, 1, 6 DESC, 3;
END;
$$ LANGUAGE plpgsql STABLE;


-- ---------------------------------------------------------------------
-- Q6: de quantos canais cada usuário é membro e quanto paga por mês.
-- Filtro opcional: usuário (nick). Lê direto de Inscricao + NivelCanal.
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_q06_membros_por_usuario(
    p_usuario VARCHAR DEFAULT NULL
)
RETURNS TABLE (
    nick_usuario      VARCHAR,
    qtd_canais        BIGINT,
    valor_mensal_usd  NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT i.nick_membro,
           COUNT(*),
           SUM(n.valor)
      FROM Inscricao i
      JOIN NivelCanal n ON n.id_canal = i.id_canal
                       AND n.nivel    = i.nivel
     WHERE p_usuario IS NULL OR i.nick_membro = p_usuario
     GROUP BY i.nick_membro
     ORDER BY 3 DESC, 1;
END;
$$ LANGUAGE plpgsql STABLE;


-- ---------------------------------------------------------------------
-- Q7: canais que já receberam doações e a soma recebida.
-- Filtro opcional: canal (id_canal). Lê da V2.
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_q07_canais_com_doacoes(
    p_canal INTEGER DEFAULT NULL
)
RETURNS TABLE (
    id_canal INTEGER,
    nome     VARCHAR,
    soma_usd NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT d.id_canal, c.nome, d.soma_usd
      FROM vw_doacao_canal d
      JOIN Canal c ON c.id_canal = d.id_canal
     WHERE p_canal IS NULL OR d.id_canal = p_canal
     ORDER BY d.soma_usd DESC, d.id_canal;
END;
$$ LANGUAGE plpgsql STABLE;


-- ---------------------------------------------------------------------
-- Q8: top-k canais que mais recebem patrocínio. Lê da V3.
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_q08_top_canais_patrocinio(
    p_k INTEGER DEFAULT 10
)
RETURNS TABLE (
    id_canal           INTEGER,
    nome               VARCHAR,
    qtd_patrocinadores BIGINT,
    soma_patrocinio    NUMERIC
) AS $$
BEGIN
    IF p_k IS NULL OR p_k <= 0 THEN
        RAISE EXCEPTION 'Q8: k deve ser um inteiro positivo';
    END IF;
    RETURN QUERY
    SELECT p.id_canal, c.nome, p.qtd_patrocinadores, p.soma_patrocinio
      FROM vw_patrocinio_canal p
      JOIN Canal c ON c.id_canal = p.id_canal
     ORDER BY p.soma_patrocinio DESC, p.id_canal
     LIMIT p_k;
END;
$$ LANGUAGE plpgsql STABLE;


-- ---------------------------------------------------------------------
-- Q9: top-k canais que mais recebem aportes de membros (valor mensal).
-- Lê da V4.
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_q09_top_canais_membros(
    p_k INTEGER DEFAULT 10
)
RETURNS TABLE (
    id_canal        INTEGER,
    nome            VARCHAR,
    qtd_membros     BIGINT,
    soma_mensal_usd NUMERIC
) AS $$
BEGIN
    IF p_k IS NULL OR p_k <= 0 THEN
        RAISE EXCEPTION 'Q9: k deve ser um inteiro positivo';
    END IF;
    RETURN QUERY
    SELECT m.id_canal, c.nome, m.qtd_membros, m.soma_mensal_usd
      FROM vw_membros_canal m
      JOIN Canal c ON c.id_canal = m.id_canal
     ORDER BY m.soma_mensal_usd DESC, m.id_canal
     LIMIT p_k;
END;
$$ LANGUAGE plpgsql STABLE;


-- ---------------------------------------------------------------------
-- Q10: top-k canais que mais receberam doações (todos os vídeos).
-- Lê da V2.
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_q10_top_canais_doacoes(
    p_k INTEGER DEFAULT 10
)
RETURNS TABLE (
    id_canal    INTEGER,
    nome        VARCHAR,
    qtd_doacoes BIGINT,
    soma_usd    NUMERIC
) AS $$
BEGIN
    IF p_k IS NULL OR p_k <= 0 THEN
        RAISE EXCEPTION 'Q10: k deve ser um inteiro positivo';
    END IF;
    RETURN QUERY
    SELECT d.id_canal, c.nome, d.qtd_doacoes, d.soma_usd
      FROM vw_doacao_canal d
      JOIN Canal c ON c.id_canal = d.id_canal
     ORDER BY d.soma_usd DESC, d.id_canal
     LIMIT p_k;
END;
$$ LANGUAGE plpgsql STABLE;


-- ---------------------------------------------------------------------
-- Q11: top-k canais que mais faturam (patrocínio + membros + doações).
-- Lê da V5. O aporte de membros entra como valor mensal (premissa).
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_q11_top_canais_faturamento(
    p_k INTEGER DEFAULT 10
)
RETURNS TABLE (
    id_canal   INTEGER,
    nome       VARCHAR,
    patrocinio NUMERIC,
    membros    NUMERIC,
    doacoes    NUMERIC,
    total      NUMERIC
) AS $$
BEGIN
    IF p_k IS NULL OR p_k <= 0 THEN
        RAISE EXCEPTION 'Q11: k deve ser um inteiro positivo';
    END IF;
    RETURN QUERY
    SELECT r.id_canal, r.nome, r.patrocinio, r.membros, r.doacoes, r.total
      FROM vw_receita_canal r
     ORDER BY r.total DESC, r.id_canal
     LIMIT p_k;
END;
$$ LANGUAGE plpgsql STABLE;


-- ---------------------------------------------------------------------
-- Q12 (desafio): top-k plataformas por quantidade de streamers e canais.
-- Filtro opcional: plataforma. Streamer = dono de canal na plataforma.
-- Ordena por streamers e, no empate, por canais.
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_q12_top_plataformas(
    p_k          INTEGER DEFAULT NULL,
    p_plataforma INTEGER DEFAULT NULL
)
RETURNS TABLE (
    nro_plataforma INTEGER,
    nome           VARCHAR,
    qtd_streamers  BIGINT,
    qtd_canais     BIGINT
) AS $$
BEGIN
    IF p_k IS NOT NULL AND p_k <= 0 THEN
        RAISE EXCEPTION 'Q12: k deve ser um inteiro positivo';
    END IF;
    RETURN QUERY
    SELECT pl.nro,
           pl.nome,
           COUNT(DISTINCT c.nick_streamer),
           COUNT(c.id_canal)
      FROM Plataforma pl
      LEFT JOIN Canal c ON c.nro_plataforma = pl.nro
     WHERE p_plataforma IS NULL OR pl.nro = p_plataforma
     GROUP BY pl.nro, pl.nome
     ORDER BY 3 DESC, 4 DESC, 1
     LIMIT p_k;
END;
$$ LANGUAGE plpgsql STABLE;
