-- =====================================================================
-- PROJETO DE BANCO DE DADOS 2026/2 - UFF - Prof. Marcos Bedo
-- create_constraints.sql
-- =====================================================================
-- Execute depois de create_tables.sql.
-- Ordem: (1) PRIMARY KEY, (2) UNIQUE, (3) FOREIGN KEY, (4) CHECK.
-- PK/UNIQUE vêm antes de FK porque toda FOREIGN KEY precisa que a
-- coluna referenciada já tenha uma constraint de unicidade.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) PRIMARY KEY
-- ---------------------------------------------------------------------
ALTER TABLE Empresa          ADD CONSTRAINT pk_empresa PRIMARY KEY (nro);
ALTER TABLE Conversao        ADD CONSTRAINT pk_conversao PRIMARY KEY (moeda);
ALTER TABLE Plataforma       ADD CONSTRAINT pk_plataforma PRIMARY KEY (nro);
ALTER TABLE Pais             ADD CONSTRAINT pk_pais PRIMARY KEY (DDI);
ALTER TABLE Usuario          ADD CONSTRAINT pk_usuario PRIMARY KEY (nick);
ALTER TABLE PlataformaUsuario ADD CONSTRAINT pk_plataforma_usuario PRIMARY KEY (nro_plataforma, nick_usuario);
ALTER TABLE StreamerPais     ADD CONSTRAINT pk_streamer_pais PRIMARY KEY (nick_streamer, ddi_pais);
ALTER TABLE EmpresaPais      ADD CONSTRAINT pk_empresa_pais PRIMARY KEY (nro_empresa, ddi_pais);
ALTER TABLE Canal            ADD CONSTRAINT pk_canal PRIMARY KEY (id_canal);
ALTER TABLE Patrocinio       ADD CONSTRAINT pk_patrocinio PRIMARY KEY (id_patrocinio);
ALTER TABLE NivelCanal       ADD CONSTRAINT pk_nivel_canal PRIMARY KEY (id_nivel_canal);
ALTER TABLE Inscricao        ADD CONSTRAINT pk_inscricao PRIMARY KEY (id_inscricao);
ALTER TABLE Video            ADD CONSTRAINT pk_video PRIMARY KEY (id_video);
ALTER TABLE Participa        ADD CONSTRAINT pk_participa PRIMARY KEY (id_video, nick_streamer);
ALTER TABLE Comentario       ADD CONSTRAINT pk_comentario PRIMARY KEY (id_comentario);
ALTER TABLE Doacao           ADD CONSTRAINT pk_doacao PRIMARY KEY (id_doacao);
ALTER TABLE BitCoin          ADD CONSTRAINT pk_bitcoin PRIMARY KEY (id_doacao);
ALTER TABLE PayPal           ADD CONSTRAINT pk_paypal PRIMARY KEY (id_doacao);
ALTER TABLE CartaoCredito    ADD CONSTRAINT pk_cartao_credito PRIMARY KEY (id_doacao);
ALTER TABLE MecanismoPlat    ADD CONSTRAINT pk_mecanismo_plat PRIMARY KEY (id_doacao);

-- ---------------------------------------------------------------------
-- 2) UNIQUE
-- ---------------------------------------------------------------------
ALTER TABLE Plataforma  ADD CONSTRAINT unq_plataforma_nome UNIQUE (nome);
ALTER TABLE Pais        ADD CONSTRAINT unq_pais_nome UNIQUE (nome);
ALTER TABLE Usuario     ADD CONSTRAINT unq_usuario_email UNIQUE (email);
ALTER TABLE Canal       ADD CONSTRAINT unq_canal_plataforma UNIQUE (nome, nro_plataforma);
ALTER TABLE Patrocinio  ADD CONSTRAINT unq_empresa_canal UNIQUE (nro_empresa, id_canal);
ALTER TABLE NivelCanal  ADD CONSTRAINT unq_canal_nivel UNIQUE (id_canal, nivel);
ALTER TABLE Inscricao   ADD CONSTRAINT unq_membro_canal UNIQUE (nick_membro, id_canal);
ALTER TABLE Video       ADD CONSTRAINT unq_video_canal UNIQUE (id_canal, titulo, dataH);
ALTER TABLE Comentario  ADD CONSTRAINT unq_video_usuario_seq UNIQUE (id_video, nick_usuario, seq);
ALTER TABLE Doacao      ADD CONSTRAINT unq_comentario_seq_pg UNIQUE (id_comentario, seq_pg);
ALTER TABLE BitCoin     ADD CONSTRAINT unq_bitcoin_txid UNIQUE (TxID);
ALTER TABLE PayPal      ADD CONSTRAINT unq_paypal_id UNIQUE (IdPayPal);

-- ---------------------------------------------------------------------
-- 3) FOREIGN KEY
-- ---------------------------------------------------------------------
ALTER TABLE Plataforma ADD CONSTRAINT fk_plataforma_empresa_fund
    FOREIGN KEY (empresa_fund) REFERENCES Empresa(nro) ON DELETE SET NULL;
ALTER TABLE Plataforma ADD CONSTRAINT fk_plataforma_empresa_respo
    FOREIGN KEY (empresa_respo) REFERENCES Empresa(nro) ON DELETE SET NULL;

ALTER TABLE Pais ADD CONSTRAINT fk_pais_moeda
    FOREIGN KEY (moeda) REFERENCES Conversao(moeda) ON DELETE RESTRICT;

ALTER TABLE Usuario ADD CONSTRAINT fk_usuario_pais
    FOREIGN KEY (pais_residencia) REFERENCES Pais(DDI) ON DELETE RESTRICT;

ALTER TABLE PlataformaUsuario ADD CONSTRAINT fk_platusuario_plataforma
    FOREIGN KEY (nro_plataforma) REFERENCES Plataforma(nro) ON DELETE CASCADE;
ALTER TABLE PlataformaUsuario ADD CONSTRAINT fk_platusuario_usuario
    FOREIGN KEY (nick_usuario) REFERENCES Usuario(nick) ON DELETE CASCADE;

ALTER TABLE StreamerPais ADD CONSTRAINT fk_streamerpais_usuario
    FOREIGN KEY (nick_streamer) REFERENCES Usuario(nick) ON DELETE CASCADE;
ALTER TABLE StreamerPais ADD CONSTRAINT fk_streamerpais_pais
    FOREIGN KEY (ddi_pais) REFERENCES Pais(DDI) ON DELETE CASCADE;

ALTER TABLE EmpresaPais ADD CONSTRAINT fk_empresapais_empresa
    FOREIGN KEY (nro_empresa) REFERENCES Empresa(nro) ON DELETE CASCADE;
ALTER TABLE EmpresaPais ADD CONSTRAINT fk_empresapais_pais
    FOREIGN KEY (ddi_pais) REFERENCES Pais(DDI) ON DELETE CASCADE;

ALTER TABLE Canal ADD CONSTRAINT fk_canal_plataforma
    FOREIGN KEY (nro_plataforma) REFERENCES Plataforma(nro) ON DELETE CASCADE;
ALTER TABLE Canal ADD CONSTRAINT fk_canal_streamer
    FOREIGN KEY (nick_streamer) REFERENCES Usuario(nick) ON DELETE RESTRICT;

ALTER TABLE Patrocinio ADD CONSTRAINT fk_patrocinio_empresa
    FOREIGN KEY (nro_empresa) REFERENCES Empresa(nro) ON DELETE CASCADE;
ALTER TABLE Patrocinio ADD CONSTRAINT fk_patrocinio_canal
    FOREIGN KEY (id_canal) REFERENCES Canal(id_canal) ON DELETE CASCADE;

ALTER TABLE NivelCanal ADD CONSTRAINT fk_nivelcanal_canal
    FOREIGN KEY (id_canal) REFERENCES Canal(id_canal) ON DELETE CASCADE;

ALTER TABLE Inscricao ADD CONSTRAINT fk_inscricao_membro
    FOREIGN KEY (nick_membro) REFERENCES Usuario(nick) ON DELETE CASCADE;
ALTER TABLE Inscricao ADD CONSTRAINT fk_inscricao_canal
    FOREIGN KEY (id_canal) REFERENCES Canal(id_canal) ON DELETE CASCADE;
ALTER TABLE Inscricao ADD CONSTRAINT fk_inscricao_nivel
    FOREIGN KEY (id_nivel_canal) REFERENCES NivelCanal(id_nivel_canal) ON DELETE CASCADE;

ALTER TABLE Video ADD CONSTRAINT fk_video_canal
    FOREIGN KEY (id_canal) REFERENCES Canal(id_canal) ON DELETE CASCADE;

ALTER TABLE Participa ADD CONSTRAINT fk_participa_video
    FOREIGN KEY (id_video) REFERENCES Video(id_video) ON DELETE CASCADE;
ALTER TABLE Participa ADD CONSTRAINT fk_participa_streamer
    FOREIGN KEY (nick_streamer) REFERENCES Usuario(nick) ON DELETE CASCADE;

ALTER TABLE Comentario ADD CONSTRAINT fk_comentario_video
    FOREIGN KEY (id_video) REFERENCES Video(id_video) ON DELETE CASCADE;
ALTER TABLE Comentario ADD CONSTRAINT fk_comentario_usuario
    FOREIGN KEY (nick_usuario) REFERENCES Usuario(nick) ON DELETE CASCADE;

ALTER TABLE Doacao ADD CONSTRAINT fk_doacao_comentario
    FOREIGN KEY (id_comentario) REFERENCES Comentario(id_comentario) ON DELETE CASCADE;

ALTER TABLE BitCoin ADD CONSTRAINT fk_bitcoin_doacao
    FOREIGN KEY (id_doacao) REFERENCES Doacao(id_doacao) ON DELETE CASCADE;
ALTER TABLE PayPal ADD CONSTRAINT fk_paypal_doacao
    FOREIGN KEY (id_doacao) REFERENCES Doacao(id_doacao) ON DELETE CASCADE;
ALTER TABLE CartaoCredito ADD CONSTRAINT fk_cartaocredito_doacao
    FOREIGN KEY (id_doacao) REFERENCES Doacao(id_doacao) ON DELETE CASCADE;
ALTER TABLE MecanismoPlat ADD CONSTRAINT fk_mecanismoplat_doacao
    FOREIGN KEY (id_doacao) REFERENCES Doacao(id_doacao) ON DELETE CASCADE;

-- ---------------------------------------------------------------------
-- 4) CHECK
-- ---------------------------------------------------------------------
ALTER TABLE Conversao   ADD CONSTRAINT chk_conversao_fator CHECK (fator_conver > 0);
ALTER TABLE Plataforma  ADD CONSTRAINT chk_plataforma_users CHECK (qtd_users >= 0);
ALTER TABLE PlataformaUsuario ADD CONSTRAINT chk_platusuario_nro CHECK (nro_usuario > 0);
ALTER TABLE Canal       ADD CONSTRAINT chk_canal_tipo CHECK (tipo IN ('privado', 'publico', 'misto'));
ALTER TABLE Canal       ADD CONSTRAINT chk_canal_views CHECK (qtd_visualizacoes >= 0);
ALTER TABLE Patrocinio  ADD CONSTRAINT chk_patrocinio_valor CHECK (valor > 0);
ALTER TABLE NivelCanal  ADD CONSTRAINT chk_nivelcanal_nivel CHECK (nivel > 0);
ALTER TABLE NivelCanal  ADD CONSTRAINT chk_nivelcanal_valor CHECK (valor >= 0);
ALTER TABLE Video       ADD CONSTRAINT chk_video_simul CHECK (visu_simul >= 0);
ALTER TABLE Video       ADD CONSTRAINT chk_video_total CHECK (visu_total >= 0);
ALTER TABLE Comentario  ADD CONSTRAINT chk_comentario_seq CHECK (seq > 0);
ALTER TABLE Doacao      ADD CONSTRAINT chk_doacao_seqpg CHECK (seq_pg > 0);
ALTER TABLE Doacao      ADD CONSTRAINT chk_doacao_valor CHECK (valor > 0);
ALTER TABLE Doacao      ADD CONSTRAINT chk_doacao_status CHECK (status IN ('recusado', 'recebido', 'lido'));
ALTER TABLE MecanismoPlat ADD CONSTRAINT chk_mecanismoplat_seq CHECK (seq_plataforma > 0);
