-- ============================================================================
-- IMPORTAÇÃO DE CARCINICULTORES
--
-- Pré-requisitos:
--   - schemas cadastro, mapa e crm criados;
--   - regra e histórico (04_regras) executados;
--   - CSV completo carregado em mapa.origem_carcinicultura_csv.
--
-- A carga é limitada aos CNAEs 321302 e 322102. Execute uma vez e valide pelo
-- arquivo 03 antes de repetir qualquer operação.
-- ============================================================================

begin;

-- Converte somente os campos necessários. A tabela de origem preserva o CSV
-- completo; os aplicativos nunca consultam essa visão temporária.
create temporary view migracao_carcinicultura_origem as
with base as (
    select
        linha_origem,
        case
            when cliente_id ~ '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$'
                then cliente_id::uuid
        end as cliente_id_legado,
        nullif(trim(razao_social), '') as razao_social,
        nullif(trim(nome_fantasia), '') as nome_fantasia,
        nullif(trim(situacao_cadastral), '') as situacao_cadastral,
        nullif(trim(logradouro), '') as logradouro,
        nullif(trim(bairro), '') as bairro,
        nullif(trim(municipio), '') as municipio,
        nullif(upper(trim(uf)), '') as uf,
        nullif(trim(contato_nome), '') as contato_nome,
        nullif(trim(contato_cargo), '') as contato_cargo,
        nullif(trim(coalesce(telefone_1, telefone)), '') as telefone,
        nullif(trim(whatsapp), '') as whatsapp,
        nullif(lower(trim(email)), '') as email,
        case
            when upper(trim(origem_registro)) = 'CADASTRO_CAMPO' then 'CADASTRO_CAMPO'
            else 'IMPORTACAO_MAPA'
        end as origem,
        nullif(regexp_replace(
            coalesce(nullif(trim(cnpj_normalizado), ''), cnpj, ''),
            '[^0-9]', '', 'g'
        ), '') as cnpj_digitos,
        nullif(regexp_replace(coalesce(cep, ''), '[^0-9]', '', 'g'), '') as cep_digitos,
        case
            when replace(nullif(trim(latitude), ''), ',', '.') ~ '^-?[0-9]+([.][0-9]+)?$'
                then replace(trim(latitude), ',', '.')::numeric(10,7)
        end as latitude_origem,
        case
            when replace(nullif(trim(longitude), ''), ',', '.') ~ '^-?[0-9]+([.][0-9]+)?$'
                then replace(trim(longitude), ',', '.')::numeric(10,7)
        end as longitude_origem,
        case
            when replace(nullif(trim(latitude_confirmada), ''), ',', '.') ~ '^-?[0-9]+([.][0-9]+)?$'
                then replace(trim(latitude_confirmada), ',', '.')::numeric(10,7)
        end as latitude_confirmada_num,
        case
            when replace(nullif(trim(longitude_confirmada), ''), ',', '.') ~ '^-?[0-9]+([.][0-9]+)?$'
                then replace(trim(longitude_confirmada), ',', '.')::numeric(10,7)
        end as longitude_confirmada_num,
        case
            when replace(nullif(trim(localizacao_precisao_m), ''), ',', '.') ~ '^[0-9]+([.][0-9]+)?$'
                then replace(trim(localizacao_precisao_m), ',', '.')::numeric(10,2)
        end as precisao_m_num,
        nullif(trim(localizacao_status), '') as localizacao_status,
        nullif(trim(localizacao_fonte), '') as localizacao_fonte,
        nullif(trim(localizacao_observacao), '') as localizacao_observacao,
        case
            when nullif(trim(localizacao_confirmada_em), '') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}'
                then localizacao_confirmada_em::timestamptz
        end as confirmado_em_origem,
        nullif(trim(localizacao_confirmada_por), '') as confirmado_por_legado
    from mapa.origem_carcinicultura_csv
    where substring(cnae from '^[[:space:]]*([0-9]{5,7})') in ('321302', '322102')
), normalizada as (
    select
        *,
        case
            when cnpj_digitos ~ '^[0-9]{14}$' then cnpj_digitos
        end as cnpj_normalizado_final,
        case
            when cep_digitos ~ '^[0-9]{8}$' then cep_digitos
        end as cep_normalizado_final,
        case
            when upper(localizacao_status) = 'CONFIRMADA_CAMPO'
             and latitude_confirmada_num is not null
             and longitude_confirmada_num is not null
             and confirmado_em_origem is not null
             and confirmado_por_legado is not null
                then true
            else false
        end as ponto_confirmado
    from base
)
select
    linha_origem,
    cliente_id_legado,
    razao_social,
    nome_fantasia,
    situacao_cadastral,
    logradouro,
    bairro,
    municipio,
    uf,
    cep_normalizado_final as cep,
    contato_nome,
    contato_cargo,
    telefone,
    whatsapp,
    email,
    origem,
    cnpj_normalizado_final as cnpj,
    case
        when ponto_confirmado then latitude_confirmada_num
        else latitude_origem
    end as latitude,
    case
        when ponto_confirmado then longitude_confirmada_num
        else longitude_origem
    end as longitude,
    case
        when ponto_confirmado then 'CONFIRMADO_CAMPO'
        when latitude_origem is not null and longitude_origem is not null then 'APROXIMADO_MUNICIPIO'
        else 'PENDENTE'
    end as status_confirmacao,
    case
        when ponto_confirmado then coalesce(localizacao_fonte, 'CAMPO_LEGADO')
        when latitude_origem is not null and longitude_origem is not null then 'SEDE_MUNICIPIO_LEGADO'
        else 'SEM_LOCALIZACAO'
    end as fonte_localizacao,
    precisao_m_num as precisao_m,
    case when ponto_confirmado then confirmado_em_origem end as confirmado_em,
    case when ponto_confirmado then confirmado_por_legado end as confirmado_por_legado,
    localizacao_observacao as observacao
from normalizada;

do $$
begin
    if not exists (select 1 from migracao_carcinicultura_origem) then
        raise exception 'Nenhum CNAE de carcinicultura foi encontrado na tabela de origem.';
    end if;
end;
$$;

-- Registra o arquivo/lote antes de criar os cadastros.
create temporary table migracao_carcinicultura_contexto
on commit drop
as
with importacao_criada as (
    insert into mapa.importacoes (
        nome,
        arquivo_bucket,
        arquivo_caminho,
        total_linhas,
        observacao
    )
    select
        'Base completa — carcinicultura',
        'importacoes-privadas',
        'mapa/2026-09-19/base-completa-mapa.csv',
        count(*),
        'Primeira migração da vertical de carcinicultura.'
    from migracao_carcinicultura_origem
    returning importacao_id
)
select * from importacao_criada;

-- Primeiro complementa uma empresa que já exista por UUID legado ou CNPJ.
-- A importação não sobrescreve enriquecimentos que a equipe tenha feito depois.
update cadastro.empresas destino
set cnpj = coalesce(destino.cnpj, origem.cnpj),
    razao_social = coalesce(destino.razao_social, origem.razao_social),
    nome_fantasia = coalesce(destino.nome_fantasia, origem.nome_fantasia),
    categoria = 'CARCINICULTOR',
    situacao_cadastral = coalesce(destino.situacao_cadastral, origem.situacao_cadastral),
    logradouro = coalesce(destino.logradouro, origem.logradouro),
    bairro = coalesce(destino.bairro, origem.bairro),
    municipio = coalesce(destino.municipio, origem.municipio),
    uf = coalesce(destino.uf, origem.uf),
    cep = coalesce(destino.cep, origem.cep),
    contato_nome = coalesce(destino.contato_nome, origem.contato_nome),
    contato_cargo = coalesce(destino.contato_cargo, origem.contato_cargo),
    telefone = coalesce(destino.telefone, origem.telefone),
    whatsapp = coalesce(destino.whatsapp, origem.whatsapp),
    email = coalesce(destino.email, origem.email),
    atualizado_em = now()
from migracao_carcinicultura_origem origem
where (origem.cliente_id_legado is not null and destino.cliente_id_legado = origem.cliente_id_legado)
   or (origem.cnpj is not null and destino.cnpj = origem.cnpj);

-- Depois insere apenas empresas que ainda não existiam no novo cadastro.
insert into cadastro.empresas (
    cnpj,
    razao_social,
    nome_fantasia,
    categoria,
    situacao_cadastral,
    logradouro,
    bairro,
    municipio,
    uf,
    cep,
    contato_nome,
    contato_cargo,
    telefone,
    whatsapp,
    email,
    cliente_id_legado,
    origem
)
select
    origem.cnpj,
    origem.razao_social,
    origem.nome_fantasia,
    'CARCINICULTOR',
    origem.situacao_cadastral,
    origem.logradouro,
    origem.bairro,
    origem.municipio,
    origem.uf,
    origem.cep,
    origem.contato_nome,
    origem.contato_cargo,
    origem.telefone,
    origem.whatsapp,
    origem.email,
    origem.cliente_id_legado,
    origem.origem
from migracao_carcinicultura_origem origem
where not exists (
    select 1
    from cadastro.empresas destino
    where (origem.cliente_id_legado is not null and destino.cliente_id_legado = origem.cliente_id_legado)
       or (origem.cnpj is not null and destino.cnpj = origem.cnpj)
);

-- O ponto confirmado já existente no novo banco nunca é trocado por uma
-- aproximação antiga. Uma confirmação trazida da origem pode elevar um ponto.
insert into mapa.pontos as destino (
    empresa_id,
    latitude,
    longitude,
    status_confirmacao,
    fonte_localizacao,
    precisao_m,
    confirmado_em,
    confirmado_por_legado,
    observacao
)
select
    empresa.empresa_id,
    origem.latitude,
    origem.longitude,
    origem.status_confirmacao,
    origem.fonte_localizacao,
    origem.precisao_m,
    origem.confirmado_em,
    origem.confirmado_por_legado,
    origem.observacao
from migracao_carcinicultura_origem origem
join cadastro.empresas empresa
    on (origem.cliente_id_legado is not null and empresa.cliente_id_legado = origem.cliente_id_legado)
    or (origem.cnpj is not null and empresa.cnpj = origem.cnpj)
on conflict (empresa_id) do update
set latitude = case
        when destino.status_confirmacao = 'CONFIRMADO_CAMPO' then destino.latitude
        else excluded.latitude
    end,
    longitude = case
        when destino.status_confirmacao = 'CONFIRMADO_CAMPO' then destino.longitude
        else excluded.longitude
    end,
    status_confirmacao = case
        when destino.status_confirmacao = 'CONFIRMADO_CAMPO' then destino.status_confirmacao
        else excluded.status_confirmacao
    end,
    fonte_localizacao = case
        when destino.status_confirmacao = 'CONFIRMADO_CAMPO' then destino.fonte_localizacao
        else excluded.fonte_localizacao
    end,
    precisao_m = case
        when destino.status_confirmacao = 'CONFIRMADO_CAMPO' then destino.precisao_m
        else excluded.precisao_m
    end,
    confirmado_em = case
        when destino.status_confirmacao = 'CONFIRMADO_CAMPO' then destino.confirmado_em
        else excluded.confirmado_em
    end,
    confirmado_por_legado = case
        when destino.status_confirmacao = 'CONFIRMADO_CAMPO' then destino.confirmado_por_legado
        else excluded.confirmado_por_legado
    end,
    observacao = coalesce(destino.observacao, excluded.observacao),
    atualizado_em = now();

-- Relaciona o novo lote à linha original de cada carcinicultor.
insert into mapa.importacao_empresas (
    importacao_id,
    empresa_id,
    linha_origem
)
select
    contexto.importacao_id,
    empresa.empresa_id,
    origem.linha_origem::integer
from migracao_carcinicultura_origem origem
cross join migracao_carcinicultura_contexto contexto
join cadastro.empresas empresa
    on (origem.cliente_id_legado is not null and empresa.cliente_id_legado = origem.cliente_id_legado)
    or (origem.cnpj is not null and empresa.cnpj = origem.cnpj)
on conflict (importacao_id, empresa_id) do nothing;

commit;
