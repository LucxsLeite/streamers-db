-- =====================================================================
-- PROJETO DE BANCO DE DADOS 2026/2 - UFF - Prof. Marcos Bedo
-- create_tables.sql
-- =====================================================================
-- Apenas estrutura de colunas (tipo, NOT NULL, DEFAULT, identidade).
-- PRIMARY KEY, FOREIGN KEY, UNIQUE e CHECK ficam em create_constraints.sql,
-- que deve ser executado logo em seguida.
-- =====================================================================

-- 1. Tabelas Base (Sem Dependências de FK)

CREATE TABLE Empresa (
    nro BIGINT GENERATED ALWAYS AS IDENTITY,
    nome VARCHAR(150) NOT NULL,
    nome_fantasia VARCHAR(150)
);

CREATE TABLE Conversao (
    moeda VARCHAR(10),
    nome VARCHAR(50) NOT NULL,
    fator_conver NUMERIC(12, 6) NOT NULL
);

-- 2. Entidades Dependentes do Primeiro Nível

CREATE TABLE Plataforma (
    nro INT GENERATED ALWAYS AS IDENTITY,
    nome VARCHAR(100) NOT NULL,
    qtd_users INT NOT NULL DEFAULT 0,          -- atributo derivado, atualizado por trigger
    empresa_fund BIGINT,
    empresa_respo BIGINT,
    data_fund DATE
);

CREATE TABLE Pais (
    DDI INT,
    nome VARCHAR(100) NOT NULL,
    moeda VARCHAR(10) NOT NULL
);

-- 3. Usuários e Associação com Países / Empresas

CREATE TABLE Usuario (
    nick VARCHAR(50),
    email VARCHAR(150) NOT NULL,
    data_nasc DATE NOT NULL,
    telefone VARCHAR(30),
    end_postal TEXT,
    pais_residencia INT NOT NULL
);

CREATE TABLE PlataformaUsuario (
    nro_plataforma INT,
    nick_usuario VARCHAR(50),
    nro_usuario INT NOT NULL
);

CREATE TABLE StreamerPais (
    nick_streamer VARCHAR(50),
    ddi_pais INT,
    nro_passaporte VARCHAR(50) NOT NULL
);

CREATE TABLE EmpresaPais (
    nro_empresa BIGINT,
    ddi_pais INT,
    id_nacional VARCHAR(50) NOT NULL
);

-- 4. Canais, Níveis, Inscrições e Patrocínios

CREATE TABLE Canal (
    id_canal BIGINT GENERATED ALWAYS AS IDENTITY,
    nome VARCHAR(100) NOT NULL,
    nro_plataforma INT NOT NULL,
    tipo VARCHAR(50) NOT NULL,
    data DATE NOT NULL DEFAULT CURRENT_DATE,
    descricao TEXT,
    qtd_visualizacoes BIGINT NOT NULL DEFAULT 0,   -- atributo derivado, atualizado por trigger
    nick_streamer VARCHAR(50) NOT NULL
);

CREATE TABLE Patrocinio (
    id_patrocinio BIGINT GENERATED ALWAYS AS IDENTITY,
    nro_empresa BIGINT NOT NULL,
    id_canal BIGINT NOT NULL,
    valor NUMERIC(12, 2) NOT NULL
);

CREATE TABLE NivelCanal (
    id_nivel_canal BIGINT GENERATED ALWAYS AS IDENTITY,
    id_canal BIGINT NOT NULL,
    nivel INT NOT NULL,
    valor NUMERIC(10, 2) NOT NULL,
    gif VARCHAR(255)
);

CREATE TABLE Inscricao (
    id_inscricao BIGINT GENERATED ALWAYS AS IDENTITY,
    nick_membro VARCHAR(50) NOT NULL,
    id_canal BIGINT NOT NULL,
    id_nivel_canal BIGINT NOT NULL
);

-- 5. Vídeos e Participações

CREATE TABLE Video (
    id_video BIGINT GENERATED ALWAYS AS IDENTITY,
    id_canal BIGINT NOT NULL,
    titulo VARCHAR(200) NOT NULL,
    dataH TIMESTAMP NOT NULL,
    tema VARCHAR(100),
    duracao INTERVAL NOT NULL,
    visu_simul INT NOT NULL DEFAULT 0,
    visu_total BIGINT NOT NULL DEFAULT 0       -- atributo derivado, atualizado por trigger
);

CREATE TABLE Participa (
    id_video BIGINT NOT NULL,
    nick_streamer VARCHAR(50) NOT NULL
);

-- 6. Interações e Pagamentos

CREATE TABLE Comentario (
    id_comentario BIGINT GENERATED ALWAYS AS IDENTITY,
    id_video BIGINT NOT NULL,
    nick_usuario VARCHAR(50) NOT NULL,
    seq INT NOT NULL,
    texto TEXT NOT NULL,
    dataH TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    coment_on BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE Doacao (
    id_doacao BIGINT GENERATED ALWAYS AS IDENTITY,
    id_comentario BIGINT NOT NULL,
    seq_pg INT NOT NULL,
    valor NUMERIC(10, 2) NOT NULL,
    status VARCHAR(30) NOT NULL
);

CREATE TABLE BitCoin (
    id_doacao BIGINT,
    TxID VARCHAR(100) NOT NULL
);

CREATE TABLE PayPal (
    id_doacao BIGINT,
    IdPayPal VARCHAR(100) NOT NULL
);

CREATE TABLE CartaoCredito (
    id_doacao BIGINT,
    nro VARCHAR(20) NOT NULL,
    bandeira VARCHAR(50) NOT NULL
);

CREATE TABLE MecanismoPlat (
    id_doacao BIGINT,
    seq_plataforma INT NOT NULL
);
