use std::{collections::HashMap, fs, sync::Arc, time::Duration};

use axum::{
    Router,
    extract::{Query, State},
    http::StatusCode,
    response::{IntoResponse, Json},
    routing::{get, post},
};
use serde::Deserialize;

static PORT: u16 = 3000;
static CONFIG_PATH: &str = "config.json";
static STATS_URL: &str = "http://localhost:8181/stats";

#[derive(Deserialize)]
struct Config {
    auth: Vec<AuthEntry>,
}

#[derive(Deserialize)]
struct AuthEntry {
    user: String,
    key: String,
}

#[derive(Clone)]
struct AppState {
    auth: Arc<HashMap<String, String>>,
    http: reqwest::Client,
}

#[derive(Deserialize, Debug)]
#[serde(rename_all = "snake_case")]
enum OnEvent {
    OnConnect,
    OnClose,
}

#[derive(Deserialize, Debug)]
#[allow(dead_code)]
struct SlsEventQuery {
    /// 'on_connect' | 'on_close'
    on_event: OnEvent,
    /// 'publisher'
    role_name: String,
    /// 'input/live/pack?srtauth=mykey'
    srt_url: String,
    /// '172.17.0.1'
    #[serde(default)]
    remote_ip: String,
    /// '57374'
    #[serde(default)]
    remote_port: String,
}

#[derive(Deserialize)]
struct StatsQuery {
    streamer: String,
    key: String,
}

#[derive(Deserialize)]
struct SlsStats {
    publishers: Option<serde_json::Value>,
}

fn load_auth(path: &str) -> Arc<HashMap<String, String>> {
    let text = fs::read_to_string(path).expect("missing config");
    let cfg: Config = serde_json::from_str(&text).expect("invalid config");
    Arc::new(cfg.auth.into_iter().map(|e| (e.user, e.key)).collect())
}

/// get `streamer` and `stream_key` from `srt_url`
/// in format `input/live/<streamer>?srtauth=<stream_key>`
fn parse_srt_auth(srt_url: &str) -> Option<(&str, String)> {
    let stream_name = srt_url.split('/').nth(2)?;
    let (streamer, query) = stream_name.split_once('?')?;
    let stream_key = form_urlencoded::parse(query.as_bytes())
        .into_owned()
        .collect::<HashMap<String, String>>()
        .get("srtauth")?
        .to_owned();
    Some((streamer, stream_key))
}

async fn handle_sls_event(
    State(state): State<AppState>,
    Query(query): Query<SlsEventQuery>,
) -> impl IntoResponse {
    println!("event {query:?}");
    let Some((streamer, stream_key)) = parse_srt_auth(&query.srt_url) else {
        return (StatusCode::BAD_REQUEST, "Invalid stream name".to_owned());
    };
    let role = query.role_name;
    match query.on_event {
        OnEvent::OnConnect
            if state
                .auth
                .get(streamer)
                .map(|k| k == &stream_key)
                .unwrap_or(false) =>
        {
            println!("{role} connected to {streamer}");
            (StatusCode::OK, String::new())
        }
        OnEvent::OnConnect => {
            println!("{role} connected to {streamer} with wrong key");
            (StatusCode::UNAUTHORIZED, String::new())
        }
        OnEvent::OnClose => {
            println!("{role} disconnected from {streamer}");
            (StatusCode::OK, String::new())
        }
    }
}

/// maps `http://localhost:3000/stats?streamer=<streamer>&key=<key>`
/// to   `http://localhost:8181/stats?publisher=live/stream/<streamer>&srtauth=<key>`
async fn handle_stats(
    State(state): State<AppState>,
    Query(query): Query<StatsQuery>,
) -> impl IntoResponse {
    let srt_auth = state.auth.get(&query.streamer).filter(|k| *k == &query.key);
    let Some(srt_auth) = srt_auth else {
        return Json(serde_json::json!({"status": "error"}));
    };
    let publisher = format!("live/stream/{}?srtauth={srt_auth}", query.streamer);
    let res = state
        .http
        .get(STATS_URL)
        .query(&[("publisher", publisher)])
        .send()
        .await;
    let publishers = match res {
        Ok(r) => r
            .json::<SlsStats>()
            .await
            .ok()
            .and_then(|s| s.publishers)
            .unwrap_or_else(|| serde_json::json!({})),
        Err(_) => serde_json::json!({}),
    };
    Json(serde_json::json!({"publishers": publishers, "status": "ok"}))
}

#[tokio::main]
async fn main() {
    let state = AppState {
        auth: load_auth(CONFIG_PATH),
        http: reqwest::Client::builder()
            .timeout(Duration::from_secs(2))
            .build()
            .expect("http client"),
    };
    let app = Router::new()
        .route("/stats", get(handle_stats))
        .route("/sls/event", post(handle_sls_event))
        .with_state(state);
    let addr = format!("0.0.0.0:{PORT}");
    let listener = tokio::net::TcpListener::bind(&addr)
        .await
        .unwrap_or_else(|_| panic!("failed to bind {addr}"));
    println!("Server started on {PORT}");
    axum::serve(listener, app).await.unwrap();
}
