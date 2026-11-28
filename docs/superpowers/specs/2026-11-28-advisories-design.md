# Advisory di sicurezza recenti (smzstudio.it)

Data: 2026-11-28. Stato: da approvare.

## Intento

devbar già monitora i repo dell'utente con `brew vulns`, `npm audit` e `composer audit`. Manca
la vista "cosa è uscito di recente": l'utente ha un aggregatore di advisory sul proprio sito
(https://smzstudio.it/advisories/, repo `savez/personalSite`, rigenerato ogni 6 ore) e vuole
vederlo nella categoria Sicurezza di devbar, con una ricerca. Fa parte dell'integrazione di
devvami (progetto dell'utente che diventa deprecato); la parte "Sviluppo" (PR e CI) ha un design
a parte.

## Obiettivi

- Un controllo `advisories` nel motore: elenca le advisory pubblicate negli ultimi giorni.
- Una riga nel pannello (categoria Sicurezza) con il numero di advisory gravi recenti.
- Una tabella in Dettagli con tutte le advisory recenti e un campo di ricerca (pacchetto, CVE/GHSA,
  titolo). Un clic su una riga apre la fonte nel browser.

## Non obiettivi

- Nessun confronto con i pacchetti dei repo dell'utente: lo fanno già `npm-audit`, `composer-audit`,
  `brew-vulns`.
- Nessuna ricerca su NVD e nessun codice di devvami.
- Nessuno stato "letto/non letto" e nessuna notifica di sistema.
- Nessuna modifica al sito `personalSite` (un JSON al posto dell'RSS è un'evoluzione possibile).

## Anti-obiettivi

- Un errore di rete non deve far sembrare "tutto a posto" né cancellare i dati già visti.
- Nessuna dipendenza nuova da installare: solo strumenti presenti in macOS (`curl`, `xmllint`/`xsltproc`) e `jq`, già richiesto.

## Vincoli

- Architettura esistente: la logica sta nel motore bash (`lib/checks/`), l'app disegna il JSON.
  Codici di uscita dei check: `0` c'è qualcosa da fare, `1` a posto, `2` errore, `3` non configurato.
- Un solo oggetto JSON su stdout, diagnostica su stderr. Serve uno schema in `schemas/` e la voce in `check all`.
- Cache in `~/.cache/devbar/`, `--force` la salta.
- Rete: solo un GET verso smzstudio.it, senza inviare dati dell'utente. Il README dice "nessuna telemetria": va aggiunta la frase che questo controllo scarica un feed pubblico.

## Approcci considerati

- **A. Controllo nel motore bash (scelto dall'utente).** Scarica `https://smzstudio.it/advisories/index.xml`,
  lo converte in JSON. Provabile da terminale, stesso schema degli altri controlli.
- B. L'app Swift scarica da sola il feed: rompe la regola "l'app non ha logica di controllo". Scartato.
- C. JSON dedicato sul sito: dati più puliti ma richiede prima un cambio in `personalSite`. Rimandato.

## Design

**Dati dal feed** (RSS 2.0, circa 660 KB, tutte le advisory e gli alert CERT). Per ogni `item`:
`title` come `[SEVERITY score] pacchetto — titolo` oppure `[ALERT CSIRT Italia] titolo`; `link` alla fonte;
`guid`; `pubDate`; `category` (ecosistema e gravità minuscola, oppure `alert`); `description` HTML con
CVE/GHSA e versioni di patch. Non ci sono versioni colpite.

**Controllo `advisories`:**
- Tiene le voci con `pubDate` negli ultimi `advisoriesDays` giorni (config, default 7).
- `items`: `{id, severity, score, package, ecosystem, title, published, url, source}`; per gli alert
  `package` e `score` sono vuoti e `severity` è `alert`. `id` è il CVE o GHSA se c'è, altrimenti il guid.
- `count`: advisory `critical` o `high`, più gli alert, tra quelle recenti. `rc 0` se `count > 0`, altrimenti `1`.
- `summary`: per esempio "3 advisory gravi negli ultimi 7 giorni".
- Cache 6 ore (il sito si rigenera ogni 6 ore), `--force` la salta.
- Rete assente o feed illeggibile: se c'è una cache la usa e scrive un avviso su stderr; altrimenti `rc 2`.
- Feed leggibile ma senza voci recenti: `rc 1`, `items` vuoto.

**App:**
- Riga "Advisory" nella sezione Sicurezza del pannello, con il numero; stato `action` quando `count > 0`
  (nessun effetto sull'icona, che è fissa).
- Tabella in Dettagli: gravità, punteggio, pacchetto, ecosistema, titolo, data; campo di ricerca che filtra
  per pacchetto, id o titolo; ordine di default dalla più recente; apertura di `url` nel browser.
- Intervallo di aggiornamento in `StatusStore` come gli altri controlli.

**Cose da aggiornare insieme:** `schemas/advisories.schema.json` e `all.schema.json`, `docs/RIFERIMENTO.md`
(check, chiave `advisoriesDays`), `README.md` (area e frase sulla rete), fixture e test.

## Test

Pochi, come preferisce l'utente: un test bats del controllo con un feed di prova salvato in fixture (voce
recente, voce vecchia, alert, feed rotto) e un test di contratto Swift che decodifica l'uscita. Prima della
consegna `just app-test` e `just app-build`.

## Scelte mie, da controllare

- Finestra di 7 giorni e chiave `advisoriesDays`.
- `count` conta solo `critical`, `high` e gli alert; la tabella mostra tutte le gravità.
- Cache di 6 ore, uguale al ritmo del sito.
- Come leggere l'XML (`xmllint`, `xsltproc` o altro tra gli strumenti di macOS) lo decide chi implementa.
