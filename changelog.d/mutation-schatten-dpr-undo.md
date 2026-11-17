### Behoben
- Mutationslauf: Das Schattenprojekt übersetzte nicht, wenn die .dpr des Testprojekts eine `.rc` einbindet (`{$R 'Daten.res' 'Daten.rc'}`), die mutierte Unit ohne `in '…'` nennt oder einen Unit-Namen mit Umlaut enthält; der Lauf meldete dann fälschlich, die Tests seien schon ohne Mutation nicht grün. Eine Form der .dpr, die der Lauf nicht umschreiben kann, meldet er jetzt als eigenen Grund mit der Textstelle.
- Rückgängig im Designer: Warf der Designer beim Aufräumen nach dem Zurückladen eines Schritts, erfasste Rückgängig bis zum Neustart der IDE keine Änderungen mehr.
