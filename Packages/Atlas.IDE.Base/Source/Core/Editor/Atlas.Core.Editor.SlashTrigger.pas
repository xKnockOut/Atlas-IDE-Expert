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
// Die Anfrage läuft im Hintergrund (Diagnose 06.11.2026: bis zu 3 s Hänger
// beim Tippen); die Antwort gilt nur, solange Datei und Text unverändert sind
// (StillValid), denn die Änderungen des Servers zählen auf diesen Stand.
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
    /// <summary>Gilt die Antwort für AAskedFile mit Text AAskedText noch für den Stand ANowFile, ANowText?</summary>
    class function StillValid(const AAskedFile, AAskedText, ANowFile, ANowText: string): Boolean; static;
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
  mPrevious: string;
begin
  Result := TAtlasSlashKind.None;
  if TrimLeft(ABefore) = '///' then
  begin
    Exit(TAtlasSlashKind.DocComment);
  end;
  if Trim(ABefore) <> '' then
  begin
    Exit;
  end;
  mPrevious := TrimLeft(APrevious);
  if (Length(mPrevious) >= 2) and (mPrevious[1] = '/') and IsLetter(mPrevious[2]) then
  begin
    Result := TAtlasSlashKind.Command;
  end;
end;

class function TAtlasSlashTrigger.TriggerChar(AKind: TAtlasSlashKind): string;
begin
  Result := '/';
  if AKind = TAtlasSlashKind.Command then
  begin
    Result := #10;
  end;
end;

class function TAtlasSlashTrigger.Key(const AFileName: string; ALine: Integer; AKind: TAtlasSlashKind;
  const APrevious: string): string;
begin
  Result := Format('%s|%d|%d|%s', [AnsiUpperCase(AFileName), ALine, Ord(AKind), Trim(APrevious)]);
end;

class function TAtlasSlashTrigger.StillValid(const AAskedFile, AAskedText, ANowFile, ANowText: string): Boolean;
begin
  Result := SameText(AAskedFile, ANowFile) and (AAskedText = ANowText);
end;

class function TAtlasSlashTrigger.DocCommentExpansion(const AText: string): TAtlasSnippetExpansion;
const
  // Ende einer leeren Beschreibung: ">" und der Anfang des schließenden Tags.
  cDescriptionEnd = '></';
var
  mIndex, mNumber, mStop: Integer;
  mField: TAtlasSnippetStop;
begin
  Result := Default(TAtlasSnippetExpansion);
  Result.Text := AText;
  mNumber := 0;
  mIndex := Pos(cDescriptionEnd, AText);
  while mIndex > 0 do
  begin
    Inc(mNumber);
    mField.Number := mNumber;
    // 0-basiert: das "<" hinter dem ">".
    mField.Start := mIndex;
    mField.Length := 0;
    Result.Stops := Result.Stops + [mField];
    mIndex := Pos(cDescriptionEnd, AText, mIndex + Length(cDescriptionEnd));
  end;
  if mNumber = 0 then
  begin
    Exit;
  end;
  mStop := Length(AText);
  while (mStop > 0) and CharInSet(AText[mStop], [#13, #10]) do
  begin
    Dec(mStop);
  end;
  mField.Number := 0;
  mField.Start := mStop;
  mField.Length := 0;
  Result.Stops := Result.Stops + [mField];
end;

end.
