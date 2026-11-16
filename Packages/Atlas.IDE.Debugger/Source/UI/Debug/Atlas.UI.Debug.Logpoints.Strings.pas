unit Atlas.UI.Debug.Logpoints.Strings;

// Texte der Logpunkte: Dialog, Befehle, Prüfung des Textes und Tipp, auf Deutsch und Englisch (#1455). Die Sprache
// bestimmt Base (`TAtlasStrings.Language`); jeder Aufruf liest sie neu.

interface

{$SCOPEDENUMS ON}

type
  TAtlasLogpointsTextId = (
    LogpointDialogTitle, LogpointText, LogpointTextHint, LogpointCondition, LogpointConditionHint, LogpointHits,
    LogpointSet, LogpointRemove, LogpointCancel, LogpointMissingClose, LogpointStrayClose, LogpointEmpty,
    LogpointFormats, LogpointNoEditor, LogpointFailed, LogpointSaidSet, LogpointSaidRemoved, LogpointSaidDisabled,
    LogpointSaidEnabled, LogpointSaidDeleted, LogpointTipTitle, LogpointTipOff);

  TAtlasLogpointsStrings = class
  public
    class function Text(AId: TAtlasLogpointsTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasLogpointsTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasLogpointsTextId] of string = (
    ('Logpunkt in %s',
     'Text:',
     'z. B. x={x}, Summe {Summe:0.00}',
     'Bedingung:',
     'optional, z. B. {Summe} > 1000',
     'Nur die ersten (0 = alle):',
     'Setzen',
     'Entfernen',
     'Abbrechen',
     'Zeichen %d: „{“ ohne „}“; eine Klammer als Text ist „{{“.',
     'Zeichen %d: „}“ ohne „{“; eine Klammer als Text ist „}}“.',
     'Zeichen %d: leerer Platzhalter.',
     'Platzhalter: {Ausdruck} oder {Ausdruck:Format}, Format d, x, 0.00 oder wie in Format (.2f); ohne Format bei mehreren Platzhaltern nur Strings.',
     'Atlas: Kein Editor mit Datei für den Logpunkt.',
     'Atlas: Der Debugger hat den Logpunkt nicht angelegt.',
     'Atlas: Logpunkt gesetzt: %s',
     'Atlas: Logpunkt entfernt.',
     'Atlas: %d Logpunkte ausgeschaltet.',
     'Atlas: %d Logpunkte eingeschaltet.',
     'Atlas: %d Logpunkte gelöscht.',
     'Logpunkt',
     'ausgeschaltet'),
    ('Logpoint in %s',
     'Text:',
     'e.g. x={x}, total {Total:0.00}',
     'Condition:',
     'optional, e.g. {Total} > 1000',
     'Only the first (0 = all):',
     'Set',
     'Remove',
     'Cancel',
     'Character %d: "{" without "}"; a literal brace is "{{".',
     'Character %d: "}" without "{"; a literal brace is "}}".',
     'Character %d: empty placeholder.',
     'Placeholders: {expression} or {expression:format}, format d, x, 0.00 or as in Format (.2f); without a format and with several placeholders only strings.',
     'Atlas: No editor with a file for the logpoint.',
     'Atlas: The debugger did not create the logpoint.',
     'Atlas: Logpoint set: %s',
     'Atlas: Logpoint removed.',
     'Atlas: %d logpoints disabled.',
     'Atlas: %d logpoints enabled.',
     'Atlas: %d logpoints deleted.',
     'Logpoint',
     'disabled'));

{ TAtlasLogpointsStrings }

class function TAtlasLogpointsStrings.Text(AId: TAtlasLogpointsTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasLogpointsStrings.Fmt(AId: TAtlasLogpointsTextId; const AArgs: array of const): string;
begin
  Result := Format(cTexts[TAtlasStrings.Language, AId], AArgs);
end;

end.
