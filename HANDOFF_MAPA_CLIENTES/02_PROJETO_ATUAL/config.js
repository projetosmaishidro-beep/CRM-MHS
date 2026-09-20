/*
 * ConfiguraÃ§Ã£o pÃºblica do mapa.
 *
 * A URL e a chave pÃºblica do Supabase sÃ£o informadas pelo painel ConexÃ£o e
 * ficam salvas somente neste navegador. Nenhuma credencial ou referÃªncia ao
 * banco legado Ã© mantida no cÃ³digo-fonte.
 */
window.MAPA_CLIENTES_CONFIG = Object.freeze({
  PROFILE: "unificado",
  SUPABASE_PAGE_SIZE: 1000,

  // FunÃ§Ã£o opcional para sugerir endereÃ§o ao confirmar uma localizaÃ§Ã£o.
  REVERSE_GEOCODING_FUNCTION: "",
  GOOGLE_MAPS_BROWSER_KEY: "",
  GOOGLE_MAPS_MAP_ID: ""
});
