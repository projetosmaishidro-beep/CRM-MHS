/*
 * Configuração pública do mapa.
 *
 * A URL e a chave pública do Supabase são informadas pelo painel Conexão e
 * ficam salvas somente neste navegador. Nenhuma credencial ou referência ao
 * banco legado é mantida no código-fonte.
 */
window.MAPA_CLIENTES_CONFIG = Object.freeze({
  PROFILE: "unificado",
  SUPABASE_PAGE_SIZE: 1000,

  // Função opcional para sugerir endereço ao confirmar uma localização.
  REVERSE_GEOCODING_FUNCTION: "",
  GOOGLE_MAPS_BROWSER_KEY: "",
  GOOGLE_MAPS_MAP_ID: ""
});
