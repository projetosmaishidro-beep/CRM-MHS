const url = "https://slrbjnqgzvryrganuzzr.supabase.co/rest/v1/vw_eventos?limit=1";
const key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNscmJqbnFnenZyeXJnYW51enpyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk4MTA5MjcsImV4cCI6MjEwNTM4NjkyN30.VNfubeJLfusK-13xjS7roUm8AVZ2SQ4kxcf4lD1cCZw";

fetch(url, {
  method: "GET",
  headers: {
    "apikey": key,
    "Authorization": `Bearer ${key}`,
    "Accept-Profile": "api"
  }
}).then(r => r.json()).then(console.log).catch(console.error);
