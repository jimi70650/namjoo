begin;
create extension if not exists pg_trgm;
drop table if exists stg_given,stg_surname,stg_gender,stg_translit,stg_equiv,stg_days,stg_pop;

create unlogged table stg_given(name text,name_id text,gender text,country_code text,country_name text,count bigint,pct_in_country double precision,origin text);
create unlogged table stg_surname(name text,name_id text,country_code text,country_name text,count bigint,pct_in_country double precision,origin text);
create unlogged table stg_gender(name text,name_id text,male_count bigint,female_count bigint,total_gendered bigint,p_male double precision,p_female double precision);
create unlogged table stg_translit(name_id text,name text,type text,lang_code text,localized_form text);
create unlogged table stg_equiv(name_id text,name text,type text,related_id text,related_name text,relation text);
create unlogged table stg_days(name text,name_id text,date_mmdd text,label text,occasion text,region text);
create unlogged table stg_pop(country_code text,country_name text,type text,rank integer,name text,name_id text,gender text,count bigint);

\copy stg_given FROM 'data/given-name-frequency.csv' WITH (format csv,header true,encoding 'UTF8');
\copy stg_surname FROM 'data/surname-frequency.csv' WITH (format csv,header true,encoding 'UTF8');
\copy stg_gender FROM 'data/name-gender-inference.csv' WITH (format csv,header true,encoding 'UTF8');
\copy stg_translit FROM 'data/name-transliterations.csv' WITH (format csv,header true,encoding 'UTF8');
\copy stg_equiv FROM 'data/name-equivalence.csv' WITH (format csv,header true,encoding 'UTF8');
\copy stg_days FROM 'data/name-days.csv' WITH (format csv,header true,encoding 'UTF8');
\copy stg_pop FROM 'data/popular-names-by-country-2026.csv' WITH (format csv,header true,encoding 'UTF8');

insert into public.sources(name,version,url,license,attribution)
select 'Onomaverse Names Dataset','v2026.06','https://onomaverse.com/datasets','CC BY 4.0','Names data from Onomaverse, licensed under CC BY 4.0.'
where not exists(select 1 from public.sources where name='Onomaverse Names Dataset' and version='v2026.06');

insert into public.countries(code,name)
select code,max(name) from (
 select trim(country_code) code,trim(country_name) name from stg_given
 union all select trim(country_code),trim(country_name) from stg_surname
 union all select trim(country_code),trim(country_name) from stg_pop
) x where code<>'' group by code
on conflict(code) do update set name=excluded.name;

insert into public.languages(code,name)
select code,code from (select distinct trim(lang_code) code from stg_translit where trim(lang_code)<>'') x
on conflict(code) do nothing;

insert into public.names(slug,name,latin_name,name_type,gender,source_id,source_record_id)
select min(name_id),min(name),min(name),'given',
 case when bool_or(gender like '%M%') and bool_or(gender like '%F%') then 'M;F'
      when bool_or(gender='M') then 'M'
      when bool_or(gender='F') then 'F' else null end,
 (select id from public.sources where name='Onomaverse Names Dataset' and version='v2026.06' limit 1),name_id
from stg_given where name_id<>'' group by name_id
on conflict(source_id,source_record_id)
do update set name=excluded.name,latin_name=excluded.latin_name,
gender=excluded.gender,updated_at=now();

insert into public.names(slug,name,latin_name,name_type,source_id,source_record_id)
select min(name_id),min(name),min(name),'surname',
 (select id from public.sources where name='Onomaverse Names Dataset' and version='v2026.06' limit 1),name_id
from stg_surname where name_id<>'' group by name_id
on conflict(source_id,source_record_id)
do update set name=excluded.name,latin_name=excluded.latin_name,updated_at=now();

update public.names n
set gender=case
 when g.p_male>=.95 then 'M'
 when g.p_female>=.95 then 'F'
 when g.p_male is not null and g.p_female is not null then 'M;F'
 else n.gender end,
updated_at=now()
from stg_gender g
where n.source_record_id=g.name_id and n.name_type='given';

insert into public.name_popularity
(name_id,country_id,year,occurrence,percentage,source_id)
select n.id,c.id,null,g.count,g.pct_in_country,
(select id from public.sources where name='Onomaverse Names Dataset'
and version='v2026.06' limit 1)
from stg_given g
join public.names n on n.source_record_id=g.name_id and n.name_type='given'
join public.countries c on c.code=g.country_code
on conflict do nothing;

insert into public.name_popularity
(name_id,country_id,year,occurrence,percentage,source_id)
select n.id,c.id,null,s.count,s.pct_in_country,
(select id from public.sources where name='Onomaverse Names Dataset'
and version='v2026.06' limit 1)
from stg_surname s
join public.names n on n.source_record_id=s.name_id and n.name_type='surname'
join public.countries c on c.code=s.country_code
on conflict do nothing;

insert into public.name_popularity
(name_id,country_id,year,rank,occurrence,source_id)
select n.id,c.id,2026,p.rank,p.count,
(select id from public.sources where name='Onomaverse Names Dataset'
and version='v2026.06' limit 1)
from stg_pop p
join public.names n on n.source_record_id=p.name_id
join public.countries c on c.code=p.country_code
on conflict do nothing;

insert into public.name_transliterations
(name_id,original,transliteration,language_id,system)
select n.id,t.name,t.localized_form,l.id,t.lang_code
from stg_translit t
join public.names n on n.source_record_id=t.name_id
join public.languages l on l.code=t.lang_code
where t.localized_form<>''
on conflict do nothing;

insert into public.name_variants(name_id,variant,relation)
select n.id,e.related_name,e.relation
from stg_equiv e
join public.names n on n.source_record_id=e.name_id
where e.related_name<>''
on conflict do nothing;

insert into public.name_relations(from_name_id,to_name_id,relation)
select n1.id,n2.id,e.relation
from stg_equiv e
join public.names n1 on n1.source_record_id=e.name_id
join public.names n2 on n2.source_record_id=e.related_id
where e.relation<>''
on conflict do nothing;

insert into public.name_days(name_id,month,day)
select n.id,
split_part(d.date_mmdd,'-',1)::integer,
split_part(d.date_mmdd,'-',2)::integer
from stg_days d
join public.names n on n.source_record_id=d.name_id
where d.date_mmdd ~ '^[0-9]{2}-[0-9]{2}$'
on conflict do nothing;

drop table stg_given,stg_surname,stg_gender,stg_translit,stg_equiv,stg_days,stg_pop;
commit;

analyze public.names;
analyze public.name_popularity;
analyze public.name_transliterations;
analyze public.name_relations;
