CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY);

CREATE TABLE "performance_metrics" ("id" TEXT PRIMARY KEY, "session_id" TEXT NOT NULL REFERENCES "workout_sessions"("id") ON DELETE CASCADE, "model_load_ms" INTEGER, "avg_inference_ms" DOUBLE, "p95_inference_ms" DOUBLE, "dropped_frame_ratio" DOUBLE, "avg_fps" DOUBLE, "delegate_type" TEXT, "analyzed_frame_count" INTEGER NOT NULL, "created_at" INTEGER NOT NULL, "sync_status" TEXT NOT NULL DEFAULT 'PENDING');

CREATE TABLE "rep_records" ("id" TEXT PRIMARY KEY, "set_id" TEXT NOT NULL REFERENCES "workout_sets"("id") ON DELETE CASCADE, "rep_number" INTEGER NOT NULL, "recorded_at" INTEGER NOT NULL, "duration_ms" INTEGER NOT NULL, "depth_score" DOUBLE, "form_score" DOUBLE, "checked_count" INTEGER NOT NULL, "warned_count" INTEGER NOT NULL, "is_valid" BOOLEAN NOT NULL DEFAULT 1, "error_flags" TEXT NOT NULL, "camera_angle" TEXT NOT NULL, "depth_level" TEXT, "depth_basis" TEXT, "depth_ratio" DOUBLE, "min_knee_angle" DOUBLE, "max_torso_lean" DOUBLE, "valid_frame_ratio" DOUBLE NOT NULL, "knee_toe_side" TEXT, "warning_phases" TEXT, "relaxed_form" BOOLEAN, "knee_tolerance" DOUBLE, "shallow_tolerance" DOUBLE, "sync_status" TEXT NOT NULL DEFAULT 'PENDING');

CREATE TABLE "workout_sessions" ("id" TEXT PRIMARY KEY, "user_id" TEXT, "exercise_type" TEXT NOT NULL DEFAULT 'squat', "device_model" TEXT, "os_version" TEXT, "pose_model" TEXT, "started_at" INTEGER NOT NULL, "ended_at" INTEGER, "form_thresholds" TEXT, "sync_status" TEXT NOT NULL DEFAULT 'PENDING');

CREATE TABLE "workout_sets" ("id" TEXT PRIMARY KEY, "session_id" TEXT NOT NULL REFERENCES "workout_sessions"("id") ON DELETE CASCADE, "set_number" INTEGER NOT NULL DEFAULT 1, "target_reps" INTEGER, "completed_reps" INTEGER NOT NULL DEFAULT 0, "sync_status" TEXT NOT NULL DEFAULT 'PENDING');

CREATE INDEX "idx_metrics_session_id" ON "performance_metrics"("session_id");

CREATE INDEX "idx_reps_set_id" ON "rep_records"("set_id");

CREATE INDEX "idx_sessions_started_at" ON "workout_sessions"("started_at");

CREATE INDEX "idx_sets_session_id" ON "workout_sets"("session_id");
