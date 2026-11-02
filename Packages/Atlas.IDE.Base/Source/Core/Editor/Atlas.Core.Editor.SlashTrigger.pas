unit Atlas.Core.Editor.SlashTrigger;

// Auslöser für Schnellbefehle (#293, #399) und ///-Gerüste (#88), Teil ohne
// Open Tools API. Der Code Insight-Manager der IDE kennt kein
// onTypeFormatting; Atlas erkennt die Lage nach jeder Änderung im Editor:
// - Befehl: Die Zeile über dem Cursor beginnt mit „/Wort“ (nicht „//“) und
//   vor dem Cursor steht nur Leerraum, also wurde gerade Enter gedrückt.
//   Der Server bekommt ch = #10 an der Cursorposition.
// - Gerüst: Vor dem Cursor steht nur Leerraum und „///“. Der Server bekommt
//   ch = '/'.
// Ob der Server etwas daraus macht, entscheidet er (Befehl unbekannt,
// abgeschaltet, keine Deklaration darunter). Damit Atlas nicht bei jedem
// weiteren Zeichen erneut fragt, merkt sich die IDE-Schicht den Schlüssel
// des letzten Auslösers.
// Das eingesetzte Gerüst füllt der Platzhalter-Modus (#51): je Beschreibung
// (zwischen ">" und "</") ein leerer Platzhalter, Tab springt weiter, am Ende
// steht der Cursor hinter dem letzten Tag.

interface

uses
  System.SysUtils,
  Atlas.Core.Completion.Snippets;

type
{$SCOPEDENUMS ON}
  TAtlasSlashKind = (None, Command, DocComment);
{$SCOPEDENUMS OFF}

  TAtlasSlashTrigger = class
  public
    /// <summary>APrevious: Zeile über dem Cursor; ABefore: Cursorzeile bis zum Cursor.</summary>
    class function Detect(const APrevious, ABefore: string): TAtlasSlashKind; static;
    /// <summary>Zeichen für onTypeFormatting: #10 bzw. '/'.</summary>
    class function TriggerChar(AKind: TAtlasSlashKind): string; static;
    /// <summary>Schlüssel gegen wiederholtes Auslösen an derselben Stelle.</summary>
    class function Key(const AFileName: string; ALine: Integer; AKind: TAtlasSlashKind;
      const APrevious: string): string; static;
    /// <summary>Platzhalter für ein eingesetztes ///-Gerüst AText: je leerer Beschreibung zwischen "&gt;" und
    /// "&lt;/" einer, die Endposition hinter dem letzten Tag (ohne abschließenden Zeilenumbruch). Ohne
    /// Beschreibung keine Platzhalter.</summary>
    class function DocCommentExpansion(const AText: string): TAtlasSnippetExpansion; static;
  end;

implementation

function IsLetter(AChar: Char): Boolean;
begin
  Result := CharInSet(AChar, ['A'..'Z', 'a'..'z']);
end;

class function TAtlasSlashTrigger.Detect(const APrevious, ABefore: string): TAtlasSlashKind;
var
  Previous: string;
begin
  Result := TAtlasSlashKind.None;
  if TrimLeft(ABefore) = '///' then
    Exit(TAtlasSlashKind.DocComment);
  if Trim(ABefore) <> '' then
    Exit;
  Previous := TrimLeft(APrevious);
  if (Length(Previous) >= 2) and (Previous[1] = '/') and IsLetter(Previous[2]) then
    Result := TAtlasSlashKind.Command;
end;

class function TAtlasSlashTrigger.TriggerChar(AKind: TAtlasSlashKind): string;
begin
  Result := '/';
  if AKind = TAtlasSlashKind.Command then
    Result := #10;
end;

class function TAtlasSlashTrigger.Key(const AFileName: string; ALine: Integer; AKind: TAtlasSlashKind;
  const APrevious: string): string;
begin
  Result := Format('%s|%d|%d|%s', [AnsiUpperCase(AFileName), ALine, Ord(AKind), Trim(APrevious)]);
end;

class function TAtlasSlashTrigger.DocCommentExpansion(const AText: string): TAtlasSnippetExpansion;
var
  Index, Number, Stop: Integer;
  Field: TAtlasSnippetStop;
begin
  Result := Default(TAtlasSnippetExpansion);
  Result.Text := AText;
  Number := 0;
  Index := Pos('></', AText);
  while Index > 0 do
  begin
    Inc(Number);
    Field.Number := Number;
    // 0-basiert: das "<" hinter dem ">".
    Field.Start := Index;
    Field.Length := 0;
    Result.Stops := Result.Stops + [Field];
    Index := Pos('></', AText, Index + 3);
  end;
  if Number = 0 then
    Exit;
  Stop := Length(AText);
  while (Stop > 0) and CharInSet(AText[Stop], [#13, #10]) do
    Dec(Stop);
  Field.Number := 0;
  Field.Start := Stop;
  Field.Length := 0;
  Result.Stops := Result.Stops + [Field];
end;

end.
