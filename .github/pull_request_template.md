## Cosa cambia

(breve descrizione del cambiamento)

## Perché

(motivazione: bug fix, nuova funzione, miglioria UX, refactor…)

## Test plan

- [ ] `just test` verde (motore, bats)
- [ ] `just lint` verde
- [ ] `just contract` verde (se è cambiato l'output di un comando: schema e fixture aggiornati)
- [ ] `just app-test` e `just app-build` verdi (se tocchi l'app)
- [ ] Provato a mano (se tocchi la UI: tema chiaro e scuro)
- [ ] Nessun test chiama strumenti veri (brew, colima, …) né scrive fuori da una HOME temporanea

## Principi del progetto

- [ ] Ogni azione che scrive o installa mostra il piano e chiede conferma (`--yes`)
- [ ] Ogni scrittura su file di altri programmi passa dal registro (`devbar undo` la annulla)
- [ ] Nessuna logica di controllo nell'app Swift (sta nel motore)

## Tipo di cambiamento

- [ ] Bug fix (non breaking)
- [ ] Nuova funzione (non breaking)
- [ ] Breaking change
- [ ] Refactor / chore
- [ ] Documentazione

## Note per la review

(scelte di compromesso, screenshot, issue collegate)
