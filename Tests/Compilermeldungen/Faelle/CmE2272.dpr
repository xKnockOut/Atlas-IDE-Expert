program CmE2272;

// E2272 Cannot use reserved unit name '%s'
// Erwartet: E2004
// Delphi 13 meldet hier E2004 statt E2272.

uses
  SysInit in 'Cm.Hilfe.E2272.pas'; // <- E2004

begin
end.
