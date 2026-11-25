### Tests
- Die FPC-Testläufe unter Linux rechnen Zeichenketten wie der Linux-Server in UTF-8 statt in Codepage 1252. Texte mit Zeichen außerhalb von 1252 (etwa „→“ in der Dateizeile des Statusfelds) kommen dort so heraus wie unter Delphi. Die Tests des Statusfelds laufen jetzt auch unter FPC.
