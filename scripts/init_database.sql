-- ============================================================================
-- SCRIPT D'INITIALISATION DE LA BASE DE DONNÉES AML
-- Projet: Système de Scoring de Risque Anti-Blanchiment d'Argent
-- Base de données: PostgreSQL / MySQL (compatible)
-- Version: 1.0.0
-- Date: Février 2026
-- ============================================================================

-- ============================================================================
-- SECTION 1: CRÉATION DE LA BASE DE DONNÉES
-- ============================================================================

-- Créer la base de données (décommenter selon votre SGBD)

-- Pour PostgreSQL:
-- CREATE DATABASE aml_risk_scoring
--     WITH ENCODING = 'UTF8'
--     LC_COLLATE = 'fr_FR.UTF-8'
--     LC_CTYPE = 'fr_FR.UTF-8'
--     TEMPLATE = template0;

-- Pour MySQL:
-- CREATE DATABASE aml_risk_scoring
--     CHARACTER SET utf8mb4
--     COLLATE utf8mb4_unicode_ci;

-- Utiliser la base de données
\c aml_risk_scoring;  -- PostgreSQL
-- USE aml_risk_scoring;  -- MySQL

-- ============================================================================
-- SECTION 2: SUPPRESSION DES TABLES EXISTANTES (SI BESOIN)
-- ============================================================================

-- Attention: Cette section supprime toutes les données existantes !
-- Décommenter seulement si vous voulez réinitialiser complètement la base

-- DROP TABLE IF EXISTS audit_logs CASCADE;
-- DROP TABLE IF EXISTS ml_predictions CASCADE;
-- DROP TABLE IF EXISTS client_risk_scores CASCADE;
-- DROP TABLE IF EXISTS client_flags CASCADE;
-- DROP TABLE IF EXISTS clients CASCADE;
-- DROP TABLE IF EXISTS risk_entities CASCADE;
-- DROP TABLE IF EXISTS professions CASCADE;
-- DROP TABLE IF EXISTS ml_models CASCADE;
-- DROP TABLE IF EXISTS system_config CASCADE;

-- ============================================================================
-- SECTION 3: CRÉATION DES TABLES DE RÉFÉRENCE
-- ============================================================================

-- -----------------------------------------------------------------------------
-- Table: professions
-- Description: Référentiel des professions avec niveau de risque
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS professions (
    profession_id SERIAL PRIMARY KEY,
    code VARCHAR(20) NOT NULL UNIQUE,
    libelle VARCHAR(255) NOT NULL,
    type_risque CHAR(1) CHECK (type_risque IN ('F', 'M', 'E')),
    risque_faible BOOLEAN DEFAULT FALSE,
    risque_moyen BOOLEAN DEFAULT FALSE,
    risque_eleve BOOLEAN DEFAULT FALSE,
    description TEXT,
    date_creation TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    date_modification TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    actif BOOLEAN DEFAULT TRUE
);

-- Index pour améliorer les performances
CREATE INDEX idx_professions_code ON professions(code);
CREATE INDEX idx_professions_type_risque ON professions(type_risque);

-- Commentaires
COMMENT ON TABLE professions IS 'Référentiel des professions avec classification de risque AML';
COMMENT ON COLUMN professions.type_risque IS 'F=Faible, M=Moyen, E=Élevé';

-- -----------------------------------------------------------------------------
-- Table: risk_entities
-- Description: Référentiel complet des entités de risque (audit_kyc_entity)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS risk_entities (
    entity_id SERIAL PRIMARY KEY,
    entity_type VARCHAR(50) NOT NULL,  -- Profession, Pays, Activite, FJ, Produits, etc.
    entity_code VARCHAR(100) NOT NULL,
    entity_name VARCHAR(255) NOT NULL,
    risk_level VARCHAR(10) NOT NULL,  -- RF, RM, RE
    risk_score INTEGER NOT NULL CHECK (risk_score BETWEEN 0 AND 100),
    risk_score_min INTEGER CHECK (risk_score_min BETWEEN 0 AND 100),
    risk_score_max INTEGER CHECK (risk_score_max BETWEEN 0 AND 100),
    description TEXT,
    regulatory_source VARCHAR(255),
    date_creation TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    date_modification TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    actif BOOLEAN DEFAULT TRUE,
    UNIQUE(entity_type, entity_code)
);

-- Index
CREATE INDEX idx_risk_entities_type ON risk_entities(entity_type);
CREATE INDEX idx_risk_entities_code ON risk_entities(entity_code);
CREATE INDEX idx_risk_entities_level ON risk_entities(risk_level);
CREATE INDEX idx_risk_entities_score ON risk_entities(risk_score);

-- Commentaires
COMMENT ON TABLE risk_entities IS 'Référentiel multidimensionnel des entités de risque AML';
COMMENT ON COLUMN risk_entities.entity_type IS 'Type: Profession, Pays, Activite, FormeJuridique, Produits, Distribution, Paiement';

-- ============================================================================
-- SECTION 4: CRÉATION DES TABLES DE DONNÉES CLIENTS
-- ============================================================================

-- -----------------------------------------------------------------------------
-- Table: clients
-- Description: Données principales des clients
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS clients (
    client_id SERIAL PRIMARY KEY,
    numpers BIGINT NOT NULL UNIQUE,
    cnat VARCHAR(10),
    type_id VARCHAR(10),
    carte_nationale_mask VARCHAR(50),
    titre VARCHAR(10),
    nom_client VARCHAR(255),
    nationalite VARCHAR(10),
    date_naissance DATE,
    type_personne CHAR(1) CHECK (type_personne IN ('P', 'M')),  -- P=Physique, M=Morale
    code_profession VARCHAR(20),
    sexe INTEGER CHECK (sexe IN (0, 1, 2)),  -- 0=Inconnu, 1=Homme, 2=Femme
    situation_familiale INTEGER,
    nombre_enfants VARCHAR(20),
    forme_juridique VARCHAR(20),
    matricule_fiscal VARCHAR(50),
    secteur_activite VARCHAR(50),
    kyc_nom2 VARCHAR(255),
    age INTEGER,
    categorie_age VARCHAR(20),
    date_creation TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    date_modification TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    actif BOOLEAN DEFAULT TRUE
);

-- Index pour optimisation
CREATE INDEX idx_clients_numpers ON clients(numpers);
CREATE INDEX idx_clients_nationalite ON clients(nationalite);
CREATE INDEX idx_clients_profession ON clients(code_profession);
CREATE INDEX idx_clients_type_personne ON clients(type_personne);
CREATE INDEX idx_clients_age ON clients(age);

-- Commentaires
COMMENT ON TABLE clients IS 'Données principales des clients du portefeuille';
COMMENT ON COLUMN clients.type_personne IS 'P=Personne Physique, M=Personne Morale';

-- -----------------------------------------------------------------------------
-- Table: client_flags
-- Description: Indicateurs de risque et anomalies par client
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS client_flags (
    flag_id SERIAL PRIMARY KEY,
    client_id INTEGER NOT NULL REFERENCES clients(client_id) ON DELETE CASCADE,
    flag_risque_eleve BOOLEAN DEFAULT FALSE,
    flag_mineur_profession BOOLEAN DEFAULT FALSE,
    flag_multi_enregistrements BOOLEAN DEFAULT FALSE,
    flag_age_suspect BOOLEAN DEFAULT FALSE,
    flag_nationalite_etrangere BOOLEAN DEFAULT FALSE,
    flag_pays_haut_risque BOOLEAN DEFAULT FALSE,
    flag_anomalie_ml BOOLEAN DEFAULT FALSE,
    score_risque_composite DECIMAL(5,2),
    nombre_dimensions_risque_eleve INTEGER DEFAULT 0,
    segment_client VARCHAR(50),
    date_calcul TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(client_id)
);

-- Index
CREATE INDEX idx_client_flags_client ON client_flags(client_id);
CREATE INDEX idx_client_flags_risque_eleve ON client_flags(flag_risque_eleve);
CREATE INDEX idx_client_flags_segment ON client_flags(segment_client);

-- Commentaires
COMMENT ON TABLE client_flags IS 'Indicateurs de risque et drapeaux d''alerte par client';

-- -----------------------------------------------------------------------------
-- Table: client_risk_scores
-- Description: Scores de risque multidimensionnels par client
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS client_risk_scores (
    score_id SERIAL PRIMARY KEY,
    client_id INTEGER NOT NULL REFERENCES clients(client_id) ON DELETE CASCADE,
    
    -- Scores par dimension
    score_profession DECIMAL(5,2),
    score_pays DECIMAL(5,2),
    score_activite DECIMAL(5,2),
    score_forme_juridique DECIMAL(5,2),
    score_produit DECIMAL(5,2),
    score_distribution DECIMAL(5,2),
    score_paiement DECIMAL(5,2),
    
    -- Score composite et ML
    score_composite DECIMAL(5,2) NOT NULL,
    score_ml DECIMAL(5,2),
    
    -- Catégorisation
    categorie_risque VARCHAR(20) CHECK (categorie_risque IN ('FAIBLE', 'MOYEN', 'ÉLEVÉ', 'CRITIQUE')),
    categorie_risque_ml VARCHAR(20) CHECK (categorie_risque_ml IN ('TRÈS_FAIBLE', 'FAIBLE', 'MOYEN', 'ÉLEVÉ', 'CRITIQUE')),
    
    -- Métadonnées
    model_version VARCHAR(20),
    date_calcul TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE(client_id, model_version)
);

-- Index
CREATE INDEX idx_risk_scores_client ON client_risk_scores(client_id);
CREATE INDEX idx_risk_scores_composite ON client_risk_scores(score_composite);
CREATE INDEX idx_risk_scores_ml ON client_risk_scores(score_ml);
CREATE INDEX idx_risk_scores_categorie ON client_risk_scores(categorie_risque);
CREATE INDEX idx_risk_scores_date ON client_risk_scores(date_calcul);

-- Commentaires
COMMENT ON TABLE client_risk_scores IS 'Scores de risque multidimensionnels calculés pour chaque client';

-- ============================================================================
-- SECTION 5: TABLES DE MACHINE LEARNING
-- ============================================================================

-- -----------------------------------------------------------------------------
-- Table: ml_models
-- Description: Métadonnées des modèles ML entraînés
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ml_models (
    model_id SERIAL PRIMARY KEY,
    model_name VARCHAR(100) NOT NULL,
    model_version VARCHAR(20) NOT NULL,
    model_type VARCHAR(50) NOT NULL,  -- RandomForest, GradientBoosting, etc.
    algorithm_params JSONB,
    training_date TIMESTAMP NOT NULL,
    training_samples INTEGER,
    test_samples INTEGER,
    
    -- Métriques de performance
    accuracy DECIMAL(5,4),
    precision_score DECIMAL(5,4),
    recall_score DECIMAL(5,4),
    f1_score DECIMAL(5,4),
    roc_auc DECIMAL(5,4),
    
    -- Features
    features_used JSONB,
    feature_importance JSONB,
    
    -- Métadonnées
    model_file_path VARCHAR(500),
    is_production BOOLEAN DEFAULT FALSE,
    created_by VARCHAR(100),
    notes TEXT,
    
    UNIQUE(model_name, model_version)
);

-- Index
CREATE INDEX idx_ml_models_version ON ml_models(model_version);
CREATE INDEX idx_ml_models_type ON ml_models(model_type);
CREATE INDEX idx_ml_models_production ON ml_models(is_production);

-- Commentaires
COMMENT ON TABLE ml_models IS 'Métadonnées et métriques des modèles ML entraînés';

-- -----------------------------------------------------------------------------
-- Table: ml_predictions
-- Description: Historique des prédictions ML
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ml_predictions (
    prediction_id SERIAL PRIMARY KEY,
    client_id INTEGER NOT NULL REFERENCES clients(client_id) ON DELETE CASCADE,
    model_id INTEGER NOT NULL REFERENCES ml_models(model_id),
    
    -- Prédictions
    predicted_class INTEGER,  -- 0=Normal, 1=Risque Élevé
    prediction_proba DECIMAL(5,4),
    risk_score DECIMAL(5,2),
    
    -- Features utilisées
    features_snapshot JSONB,
    
    -- Métadonnées
    prediction_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    prediction_time_ms INTEGER
);

-- Index
CREATE INDEX idx_ml_predictions_client ON ml_predictions(client_id);
CREATE INDEX idx_ml_predictions_model ON ml_predictions(model_id);
CREATE INDEX idx_ml_predictions_date ON ml_predictions(prediction_date);
CREATE INDEX idx_ml_predictions_score ON ml_predictions(risk_score);

-- Commentaires
COMMENT ON TABLE ml_predictions IS 'Historique des prédictions ML avec traçabilité complète';

-- ============================================================================
-- SECTION 6: TABLES D'AUDIT ET LOGS
-- ============================================================================

-- -----------------------------------------------------------------------------
-- Table: audit_logs
-- Description: Logs d'audit pour traçabilité et conformité
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS audit_logs (
    log_id SERIAL PRIMARY KEY,
    log_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    log_type VARCHAR(50) NOT NULL,  -- SCORING, ALERT, REVIEW, EXPORT, etc.
    user_id VARCHAR(100),
    client_id INTEGER REFERENCES clients(client_id),
    
    -- Détails de l'action
    action VARCHAR(255) NOT NULL,
    action_details JSONB,
    
    -- Résultat
    status VARCHAR(20) CHECK (status IN ('SUCCESS', 'FAILED', 'WARNING')),
    error_message TEXT,
    
    -- Traçabilité
    ip_address INET,
    session_id VARCHAR(255),
    
    -- Métadonnées
    before_values JSONB,
    after_values JSONB
);

-- Index
CREATE INDEX idx_audit_logs_timestamp ON audit_logs(log_timestamp);
CREATE INDEX idx_audit_logs_type ON audit_logs(log_type);
CREATE INDEX idx_audit_logs_user ON audit_logs(user_id);
CREATE INDEX idx_audit_logs_client ON audit_logs(client_id);
CREATE INDEX idx_audit_logs_status ON audit_logs(status);

-- Commentaires
COMMENT ON TABLE audit_logs IS 'Logs d''audit pour traçabilité complète et conformité réglementaire';

-- ============================================================================
-- SECTION 7: TABLES DE CONFIGURATION
-- ============================================================================

-- -----------------------------------------------------------------------------
-- Table: system_config
-- Description: Configuration système et paramètres
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS system_config (
    config_id SERIAL PRIMARY KEY,
    config_key VARCHAR(100) NOT NULL UNIQUE,
    config_value TEXT NOT NULL,
    config_type VARCHAR(20) CHECK (config_type IN ('STRING', 'INTEGER', 'FLOAT', 'BOOLEAN', 'JSON')),
    description TEXT,
    category VARCHAR(50),
    is_sensitive BOOLEAN DEFAULT FALSE,
    date_creation TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    date_modification TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    modified_by VARCHAR(100)
);

-- Index
CREATE INDEX idx_system_config_key ON system_config(config_key);
CREATE INDEX idx_system_config_category ON system_config(category);

-- Commentaires
COMMENT ON TABLE system_config IS 'Configuration système et paramètres de l''application';

-- ============================================================================
-- SECTION 8: INSERTION DES DONNÉES DE CONFIGURATION INITIALES
-- ============================================================================

-- Paramètres de scoring
INSERT INTO system_config (config_key, config_value, config_type, description, category) VALUES
('scoring.weight.profession', '0.35', 'FLOAT', 'Poids de la dimension Profession dans le score composite', 'SCORING'),
('scoring.weight.pays', '0.30', 'FLOAT', 'Poids de la dimension Pays dans le score composite', 'SCORING'),
('scoring.weight.activite', '0.20', 'FLOAT', 'Poids de la dimension Activité dans le score composite', 'SCORING'),
('scoring.weight.forme_juridique', '0.15', 'FLOAT', 'Poids de la dimension Forme Juridique dans le score composite', 'SCORING'),

-- Seuils de risque
('threshold.risk.critical', '80', 'INTEGER', 'Seuil pour risque CRITIQUE (score >= 80)', 'THRESHOLDS'),
('threshold.risk.high', '65', 'INTEGER', 'Seuil pour risque ÉLEVÉ (score >= 65)', 'THRESHOLDS'),
('threshold.risk.medium', '50', 'INTEGER', 'Seuil pour risque MOYEN (score >= 50)', 'THRESHOLDS'),

-- Paramètres ML
('ml.default_model', 'random_forest_v1.0', 'STRING', 'Modèle ML par défaut pour la production', 'ML'),
('ml.retraining_frequency_days', '30', 'INTEGER', 'Fréquence de réentraînement des modèles (jours)', 'ML'),
('ml.min_accuracy_threshold', '0.85', 'FLOAT', 'Seuil minimal d''accuracy pour déploiement', 'ML'),

-- Système
('system.version', '1.0.0', 'STRING', 'Version du système AML', 'SYSTEM'),
('system.environment', 'PRODUCTION', 'STRING', 'Environnement: DEVELOPMENT, STAGING, PRODUCTION', 'SYSTEM'),
('system.batch_size', '1000', 'INTEGER', 'Taille des batchs pour traitement', 'SYSTEM'),

-- Conformité
('compliance.alert_email', 'compliance@company.com', 'STRING', 'Email pour alertes de conformité', 'COMPLIANCE'),
('compliance.critical_review_required', 'true', 'BOOLEAN', 'Revue manuelle obligatoire pour risque critique', 'COMPLIANCE'),
('compliance.retention_period_years', '10', 'INTEGER', 'Période de rétention des données (années)', 'COMPLIANCE')

ON CONFLICT (config_key) DO NOTHING;

-- ============================================================================
-- SECTION 9: CRÉATION DES VUES UTILES
-- ============================================================================

-- -----------------------------------------------------------------------------
-- Vue: v_clients_high_risk
-- Description: Vue des clients à haut risque
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_clients_high_risk AS
SELECT 
    c.client_id,
    c.numpers,
    c.nom_client,
    c.nationalite,
    c.code_profession,
    c.age,
    rs.score_composite,
    rs.score_ml,
    rs.categorie_risque,
    cf.flag_risque_eleve,
    cf.flag_anomalie_ml,
    cf.segment_client,
    rs.date_calcul
FROM clients c
JOIN client_risk_scores rs ON c.client_id = rs.client_id
LEFT JOIN client_flags cf ON c.client_id = cf.client_id
WHERE rs.categorie_risque IN ('ÉLEVÉ', 'CRITIQUE')
   OR rs.score_composite >= 65
ORDER BY rs.score_composite DESC;

COMMENT ON VIEW v_clients_high_risk IS 'Vue des clients classés à haut risque ou critique';

-- -----------------------------------------------------------------------------
-- Vue: v_risk_summary_by_profession
-- Description: Résumé des risques par profession
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_risk_summary_by_profession AS
SELECT 
    c.code_profession,
    p.libelle AS profession_libelle,
    p.type_risque AS risque_referentiel,
    COUNT(c.client_id) AS nombre_clients,
    AVG(rs.score_composite) AS score_moyen,
    MIN(rs.score_composite) AS score_min,
    MAX(rs.score_composite) AS score_max,
    COUNT(CASE WHEN rs.categorie_risque = 'CRITIQUE' THEN 1 END) AS nb_critiques,
    COUNT(CASE WHEN rs.categorie_risque = 'ÉLEVÉ' THEN 1 END) AS nb_eleves,
    COUNT(CASE WHEN rs.categorie_risque = 'MOYEN' THEN 1 END) AS nb_moyens,
    COUNT(CASE WHEN rs.categorie_risque = 'FAIBLE' THEN 1 END) AS nb_faibles
FROM clients c
LEFT JOIN professions p ON c.code_profession = p.code
LEFT JOIN client_risk_scores rs ON c.client_id = rs.client_id
GROUP BY c.code_profession, p.libelle, p.type_risque
ORDER BY score_moyen DESC;

COMMENT ON VIEW v_risk_summary_by_profession IS 'Statistiques de risque agrégées par profession';

-- -----------------------------------------------------------------------------
-- Vue: v_ml_model_performance
-- Description: Performance des modèles ML
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_ml_model_performance AS
SELECT 
    model_id,
    model_name,
    model_version,
    model_type,
    training_date,
    accuracy,
    precision_score,
    recall_score,
    f1_score,
    roc_auc,
    is_production,
    RANK() OVER (PARTITION BY model_type ORDER BY f1_score DESC) AS rank_by_f1
FROM ml_models
ORDER BY training_date DESC;

COMMENT ON VIEW v_ml_model_performance IS 'Tableau de bord de performance des modèles ML';

-- ============================================================================
-- SECTION 10: FONCTIONS UTILITAIRES
-- ============================================================================

-- -----------------------------------------------------------------------------
-- Fonction: calculate_age
-- Description: Calculer l'âge à partir de la date de naissance
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION calculate_age(birth_date DATE)
RETURNS INTEGER AS $$
BEGIN
    RETURN EXTRACT(YEAR FROM AGE(CURRENT_DATE, birth_date));
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION calculate_age IS 'Calcule l''âge en années à partir de la date de naissance';

-- -----------------------------------------------------------------------------
-- Fonction: get_risk_category
-- Description: Déterminer la catégorie de risque à partir du score
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_risk_category(score DECIMAL)
RETURNS VARCHAR(20) AS $$
BEGIN
    CASE
        WHEN score >= 80 THEN RETURN 'CRITIQUE';
        WHEN score >= 65 THEN RETURN 'ÉLEVÉ';
        WHEN score >= 50 THEN RETURN 'MOYEN';
        ELSE RETURN 'FAIBLE';
    END CASE;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION get_risk_category IS 'Détermine la catégorie de risque (FAIBLE/MOYEN/ÉLEVÉ/CRITIQUE) à partir du score composite';

-- -----------------------------------------------------------------------------
-- Fonction: update_modified_timestamp
-- Description: Trigger function pour mettre à jour automatiquement date_modification
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION update_modified_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.date_modification = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION update_modified_timestamp IS 'Fonction trigger pour mettre à jour automatiquement le timestamp de modification';

-- ============================================================================
-- SECTION 11: CRÉATION DES TRIGGERS
-- ============================================================================

-- Trigger pour professions
CREATE TRIGGER trg_professions_update
    BEFORE UPDATE ON professions
    FOR EACH ROW
    EXECUTE FUNCTION update_modified_timestamp();

-- Trigger pour clients
CREATE TRIGGER trg_clients_update
    BEFORE UPDATE ON clients
    FOR EACH ROW
    EXECUTE FUNCTION update_modified_timestamp();

-- Trigger pour risk_entities
CREATE TRIGGER trg_risk_entities_update
    BEFORE UPDATE ON risk_entities
    FOR EACH ROW
    EXECUTE FUNCTION update_modified_timestamp();

-- Trigger pour system_config
CREATE TRIGGER trg_system_config_update
    BEFORE UPDATE ON system_config
    FOR EACH ROW
    EXECUTE FUNCTION update_modified_timestamp();

-- ============================================================================
-- SECTION 12: PERMISSIONS ET SÉCURITÉ
-- ============================================================================

-- Créer des rôles (à adapter selon vos besoins)

-- Rôle lecture seule (analystes, auditeurs)
-- CREATE ROLE aml_reader;
-- GRANT SELECT ON ALL TABLES IN SCHEMA public TO aml_reader;
-- GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO aml_reader;

-- Rôle lecture/écriture (data scientists, développeurs)
-- CREATE ROLE aml_writer;
-- GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO aml_writer;
-- GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO aml_writer;

-- Rôle admin (DBA)
-- CREATE ROLE aml_admin;
-- GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO aml_admin;
-- GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO aml_admin;

-- ============================================================================
-- SECTION 13: STATISTIQUES ET OPTIMISATION
-- ============================================================================

-- Analyser les tables pour optimiser les requêtes
ANALYZE clients;
ANALYZE client_risk_scores;
ANALYZE client_flags;
ANALYZE professions;
ANALYZE risk_entities;
ANALYZE ml_models;
ANALYZE ml_predictions;
ANALYZE audit_logs;

-- ============================================================================
-- SECTION 14: VÉRIFICATION DE L'INSTALLATION
-- ============================================================================

-- Afficher le résumé des tables créées
SELECT 
    table_name,
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = t.table_name) AS column_count
FROM information_schema.tables t
WHERE table_schema = 'public'
  AND table_type = 'BASE TABLE'
ORDER BY table_name;

-- ============================================================================
-- FIN DU SCRIPT D'INITIALISATION
-- ============================================================================

-- Afficher un message de succès
DO $$
BEGIN
    RAISE NOTICE '============================================================================';
    RAISE NOTICE 'INITIALISATION DE LA BASE DE DONNÉES AML TERMINÉE AVEC SUCCÈS';
    RAISE NOTICE '============================================================================';
    RAISE NOTICE '';
    RAISE NOTICE 'Tables créées:';
    RAISE NOTICE '  ✓ professions';
    RAISE NOTICE '  ✓ risk_entities';
    RAISE NOTICE '  ✓ clients';
    RAISE NOTICE '  ✓ client_flags';
    RAISE NOTICE '  ✓ client_risk_scores';
    RAISE NOTICE '  ✓ ml_models';
    RAISE NOTICE '  ✓ ml_predictions';
    RAISE NOTICE '  ✓ audit_logs';
    RAISE NOTICE '  ✓ system_config';
    RAISE NOTICE '';
    RAISE NOTICE 'Vues créées:';
    RAISE NOTICE '  ✓ v_clients_high_risk';
    RAISE NOTICE '  ✓ v_risk_summary_by_profession';
    RAISE NOTICE '  ✓ v_ml_model_performance';
    RAISE NOTICE '';
    RAISE NOTICE 'Prochaine étape: Charger les données avec load_data.sql';
    RAISE NOTICE '============================================================================';
END $$;
