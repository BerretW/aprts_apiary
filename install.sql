CREATE TABLE `aprts_bee_apiaries` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `owner_identifier` varchar(64) NOT NULL,
  `name` varchar(64) DEFAULT NULL,
  `pos_x` float DEFAULT NULL,
  `pos_y` float DEFAULT NULL,
  `pos_z` float DEFAULT NULL,
  `heading` float DEFAULT NULL,
  `radius` float NOT NULL DEFAULT 20,
  `flora_profile` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL,
  `nectar_baseline` float NOT NULL,
  `pollination_radius` float NOT NULL DEFAULT 20,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB;


CREATE TABLE IF NOT EXISTS `aprts_bee_hives` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `apiary_id` int(11) NOT NULL,
  `hive_label` varchar(32) DEFAULT NULL,
  `coords` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL DEFAULT '{"x":0.0,"y":0.0,"z":0.0,"h":0.0}' CHECK (json_valid(`coords`)),
  `state` enum('DORMANT','GROWTH','PEAK','DECLINE') NOT NULL DEFAULT 'GROWTH',
  `substate` enum('HEALTHY','DISEASED','STARVING','SWARMING','QUEENLESS','LOOTED') NOT NULL DEFAULT 'HEALTHY',
  `queen_uid` varchar(32) DEFAULT NULL,
  `bee_genetics` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `population` int(11) DEFAULT 10000,
  `stores_honey` float DEFAULT 0,
  `stores_wax` float DEFAULT 0,
  `frames_total` int(11) DEFAULT 10,
  `frames_capped` int(11) DEFAULT 0,
  `super_count` int(11) DEFAULT 0,
  `disease_progress` float DEFAULT 0,
  `mite_level` float DEFAULT 0,
  `rain_state` float DEFAULT 0,
  `rain_updated_at` timestamp NULL DEFAULT NULL,
  `last_bear_attack` timestamp NULL DEFAULT NULL,
  `last_tick` timestamp NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `apiary_id` (`apiary_id`),
  CONSTRAINT `aprts_bee_hives_ibfk_1` FOREIGN KEY (`apiary_id`) REFERENCES `aprts_bee_apiaries` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;


CREATE TABLE `aprts_bee_queens` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `hive_id` int(11) DEFAULT NULL,
  `queen_uid` varchar(36) DEFAULT NULL,
  `age_days` int(11) DEFAULT 0,
  `genetics` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `fertility` float DEFAULT 1,
  `alive` tinyint(1) DEFAULT 1,
  `origin` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `pedigree` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `quality_score` float DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `queen_uid` (`queen_uid`),
  KEY `hive_id` (`hive_id`),
  CONSTRAINT `aprts_bee_queens_ibfk_1` FOREIGN KEY (`hive_id`) REFERENCES `aprts_bee_hives` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE `aprts_bee_events` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `hive_id` int(11) DEFAULT NULL,
  `type` varchar(32) DEFAULT NULL,
  `payload` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `hive_id` (`hive_id`),
  CONSTRAINT `aprts_bee_events_ibfk_1` FOREIGN KEY (`hive_id`) REFERENCES `aprts_bee_hives` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB;