program CmE2085;

// E2085 Unit name mismatch: '%s' '%s'
// Erwartet: E1038
// Delphi 13 meldet hier E1038 statt E2085.

uses
  Cm.Hilfe.E2085 in 'Cm.Hilfe.E2085Datei.pas'; // <- E1038

begin
end.
