-- ============================================================
-- Entidades independentes
-- ============================================================

CREATE TABLE Empresa (
    nro           INTEGER      PRIMARY KEY,
    nome          VARCHAR(100) NOT NULL,
    nome_fantasia VARCHAR(100)
);

CREATE TABLE Conversao (
    moeda        VARCHAR(3)    PRIMARY KEY,
    nome         VARCHAR(50)   NOT NULL,
    fator_conver NUMERIC(12,6) NOT NULL CHECK (fator_conver > 0)
);

CREATE TABLE Pais (
    ddi   INTEGER     PRIMARY KEY CHECK (ddi > 0),
    nome  VARCHAR(60) NOT NULL,
    moeda VARCHAR(3)  NOT NULL REFERENCES Conversao(moeda)
);

-- ============================================================
-- Plataforma e empresas
-- ============================================================

CREATE TABLE Plataforma (
    nro           INTEGER     PRIMARY KEY,
    nome          VARCHAR(60) NOT NULL,
    data_fund     DATE        NOT NULL,
    empresa_fund  INTEGER     NOT NULL REFERENCES Empresa(nro),
    empresa_respo INTEGER     NOT NULL REFERENCES Empresa(nro)
);

-- Identificador nacional (ex.: CNPJ) é único dentro de cada país
CREATE TABLE EmpresaPais (
    nro_empresa INTEGER     NOT NULL REFERENCES Empresa(nro),
    ddi_pais    INTEGER     NOT NULL REFERENCES Pais(ddi),
    id_nacional VARCHAR(30) NOT NULL,
    PRIMARY KEY (nro_empresa, ddi_pais),
    UNIQUE (ddi_pais, id_nacional)
);

-- ============================================================
-- Usuários
-- ============================================================

CREATE TABLE Usuario (
    nick            VARCHAR(40)  PRIMARY KEY,
    email           VARCHAR(120) NOT NULL UNIQUE,
    data_nasc       DATE         NOT NULL,
    telefone        VARCHAR(20)  NOT NULL,
    end_postal      VARCHAR(200) NOT NULL,
    pais_residencia INTEGER      NOT NULL REFERENCES Pais(ddi)
);

CREATE TABLE PlataformaUsuario (
    nro_plataforma INTEGER     NOT NULL REFERENCES Plataforma(nro),
    nick_usuario   VARCHAR(40) NOT NULL REFERENCES Usuario(nick),
    nro_usuario    INTEGER     NOT NULL,
    PRIMARY KEY (nro_plataforma, nick_usuario),
    UNIQUE (nro_plataforma, nro_usuario)
);

-- Passaportes (N:N no ER).
CREATE TABLE StreamerPais (
    nick_streamer  VARCHAR(40) NOT NULL REFERENCES Usuario(nick),
    ddi_pais       INTEGER     NOT NULL REFERENCES Pais(ddi),
    nro_passaporte VARCHAR(30) NOT NULL,
    PRIMARY KEY (nick_streamer, ddi_pais),
    UNIQUE (ddi_pais, nro_passaporte)
);

-- ============================================================
-- Canal
-- ============================================================

CREATE TABLE Canal (
    id_canal       INTEGER     GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome           VARCHAR(80) NOT NULL,
    nro_plataforma INTEGER     NOT NULL REFERENCES Plataforma(nro),
    tipo           VARCHAR(10) NOT NULL CHECK (tipo IN ('privado', 'público', 'misto')),
    data_inicio    DATE        NOT NULL,
    descricao      TEXT,
    nick_streamer  VARCHAR(40) NOT NULL REFERENCES Usuario(nick),
    UNIQUE (nome, nro_plataforma)
);

-- Patrocínio vigente apenas (sem histórico), em USD
CREATE TABLE Patrocinio (
    nro_empresa INTEGER       NOT NULL REFERENCES Empresa(nro),
    id_canal    INTEGER       NOT NULL REFERENCES Canal(id_canal),
    valor       NUMERIC(12,2) NOT NULL CHECK (valor > 0),
    PRIMARY KEY (nro_empresa, id_canal)
);

-- Valor mensal em USD
CREATE TABLE NivelCanal (
    id_canal INTEGER       NOT NULL REFERENCES Canal(id_canal),
    nivel    VARCHAR(40)   NOT NULL,
    valor    NUMERIC(12,2) NOT NULL CHECK (valor > 0),
    gif      VARCHAR(200)  NOT NULL,
    PRIMARY KEY (id_canal, nivel)
);

-- Membros vigentes apenas (sem histórico)
CREATE TABLE Inscricao (
    id_canal    INTEGER     NOT NULL REFERENCES Canal(id_canal),
    nick_membro VARCHAR(40) NOT NULL REFERENCES Usuario(nick),
    nivel       VARCHAR(40) NOT NULL,
    PRIMARY KEY (id_canal, nick_membro),
    FOREIGN KEY (id_canal, nivel) REFERENCES NivelCanal(id_canal, nivel)
);

-- ============================================================
-- Vídeo e participação
-- ============================================================

CREATE TABLE Video (
    id_video   INTEGER      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_canal   INTEGER      NOT NULL REFERENCES Canal(id_canal),
    titulo     VARCHAR(150) NOT NULL,
    dataH      TIMESTAMP    NOT NULL,
    tema       VARCHAR(80),
    duracao    INTERVAL     NOT NULL CHECK (duracao > INTERVAL '0 seconds'),
    visu_simul INTEGER      NOT NULL CHECK (visu_simul >= 0),
    visu_total INTEGER      NOT NULL CHECK (visu_total >= 0),
    UNIQUE (id_canal, titulo, dataH),
    CHECK (visu_simul <= visu_total)
);

-- Streamers convidados em um vídeo.
CREATE TABLE Participa (
    id_video      INTEGER     NOT NULL REFERENCES Video(id_video),
    nick_streamer VARCHAR(40) NOT NULL REFERENCES Usuario(nick),
    PRIMARY KEY (id_video, nick_streamer)
);

-- ============================================================
-- Comentário
-- ============================================================

CREATE TABLE Comentario (
    id_comentario INTEGER     GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_video      INTEGER     NOT NULL REFERENCES Video(id_video),
    seq           INTEGER     NOT NULL CHECK (seq > 0),
    nick_usuario  VARCHAR(40) NOT NULL REFERENCES Usuario(nick),
    texto         TEXT        NOT NULL,
    dataH         TIMESTAMP   NOT NULL,
    coment_on     BOOLEAN     NOT NULL,   -- TRUE = online, FALSE = offline
    UNIQUE (id_video, seq)
);

-- ============================================================
-- Doação: identificada pelo próprio comentário (uma doação por comentário)
-- ============================================================

CREATE TABLE Doacao (
    id_comentario  INTEGER       PRIMARY KEY REFERENCES Comentario(id_comentario),
    moeda          VARCHAR(3)    NOT NULL REFERENCES Conversao(moeda),
    valor_original NUMERIC(12,2) NOT NULL CHECK (valor_original > 0),
    valor          NUMERIC(12,2) NOT NULL CHECK (valor > 0),   -- USD, calculado pelo trigger F
    status         VARCHAR(10)   NOT NULL CHECK (status IN ('recusado', 'recebido', 'lido'))
);

-- ============================================================
-- Meios de pagamento
-- ============================================================

-- Cartão: a bandeira depende do número (3FN)
CREATE TABLE Cartao (
    nro      VARCHAR(20) PRIMARY KEY,
    bandeira VARCHAR(30) NOT NULL
);

CREATE TABLE CartaoCredito (
    id_comentario INTEGER     PRIMARY KEY REFERENCES Doacao(id_comentario),
    nro_cartao    VARCHAR(20) NOT NULL REFERENCES Cartao(nro)
);

CREATE TABLE BitCoin (
    id_comentario INTEGER      PRIMARY KEY REFERENCES Doacao(id_comentario),
    TxID          VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE PayPal (
    id_comentario INTEGER      PRIMARY KEY REFERENCES Doacao(id_comentario),
    IdPayPal      VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE MecanismoPlat (
    id_comentario  INTEGER PRIMARY KEY REFERENCES Doacao(id_comentario),
    seq_plataforma INTEGER NOT NULL CHECK (seq_plataforma > 0)
);

CREATE INDEX idx_canal_plataforma   ON Canal (nro_plataforma);       -- consultas 4 e 12
CREATE INDEX idx_patrocinio_canal   ON Patrocinio (id_canal);        -- consultas 5, 8 e 11
CREATE INDEX idx_inscricao_membro   ON Inscricao (nick_membro);      -- consulta 6
CREATE INDEX idx_participa_streamer ON Participa (nick_streamer);    -- trigger B (checagem de participação)
CREATE INDEX idx_canal_streamer     ON Canal (nick_streamer);       -- consulta 3 (filtro) e trigger T02
