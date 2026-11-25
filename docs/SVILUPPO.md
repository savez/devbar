# Sviluppo e rilascio

Per le regole di contributo vedi [CONTRIBUTING.md](../CONTRIBUTING.md).

## Sviluppo

```
just test        # bats (motore)
just lint        # shellcheck
just contract    # rigenera le fixture di contratto dal motore e le valida contro schemas/
just app-test    # swift-testing (XCTest manca nelle Command Line Tools)
just build       # solo il bundle in app/.build/devbar.app
```

## Contratto

Motore (bash) e app (Swift) si scambiano JSON. Il contratto è scritto in `schemas/` (JSON Schema 2020-12, uno per comando, pezzi comuni in `schemas/defs.schema.json`): i campi che l'app legge sono `required` con tipo esatto, i campi extra non sono ammessi. Il motore è la verità: se l'app si aspetta altro, si corregge l'app.

- `tests/contract-fixtures.sh` produce l'output reale di ogni comando con gli stub di `tests/` e una HOME temporanea, anonimizzato, in `app/Tests/DevbarCoreTests/Fixtures/contract/<comando>.json` (le varianti sono `<comando>.<variante>.json`).
- `tests/contract.bats` valida ogni fixture contro il suo schema, ha un caso negativo per ogni schema e fallisce se le fixture registrate non sono quelle che il motore produce ora.
- `app/Tests/DevbarCoreTests/ContractTests.swift` decodifica le stesse fixture con i modelli Swift e verifica che ogni campo usato dall'app sia presente e valorizzato.

Se cambia l'output di un comando: aggiornare lo schema, lanciare `just contract` e committare le fixture.

### Come esce una release

1. i commit su `main` seguono i prefissi conventional (`feat:`, `fix:`, `refactor:`, ...);
2. al merge su `main` il workflow `.github/workflows/release.yml` fa girare release-please (Linux) che apre o aggiorna una PR di release (versione in `version.txt`, `CHANGELOG.md`);
3. il merge di quella PR crea tag e release su GitHub;
4. solo allora parte il job macOS: `just package VERSION=x.y.z` e `gh release upload` di `dist/devbar-x.y.z.zip`.

La pipeline non esegue test (girano in locale: `just test`, `just app-test`). Le action sono fissate allo SHA del commit (`googleapis/release-please-action`, `actions/checkout`; il commento accanto dice la versione), così una versione ripubblicata non può cambiare cosa gira nella pipeline. Dependabot propone gli aggiornamenti con una PR mensile (`.github/dependabot.yml`), SHA e commento compresi.

## Origine del codice

Vedi la sezione "Licenza e origine" del [README](../README.md#licenza-e-origine).
