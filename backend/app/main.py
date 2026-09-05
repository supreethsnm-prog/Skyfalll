from fastapi import FastAPI

app = FastAPI(title="WeatherGPT Backend")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
