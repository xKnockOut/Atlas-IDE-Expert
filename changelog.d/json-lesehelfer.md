### Geändert
- Listen von Strings aus JSON liest überall `TJsonRead.Strings` bzw. `TJsonRead.TrimmedStrings`: Zahlen, Wahrheitswerte und null in einer solchen Liste werden einheitlich übergangen (bisher je nach Stelle und Delphi-Version mal übernommen, mal nicht). Eine Prüfung im Build erkennt neue Kopien an ihrer Form statt am Namen.
