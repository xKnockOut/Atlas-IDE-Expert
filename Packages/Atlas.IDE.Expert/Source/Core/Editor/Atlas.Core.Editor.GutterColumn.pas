unit Atlas.Core.Editor.GutterColumn;

// Atlas-Spalte in der Zeilenleiste (#768), ohne VCL und Open Tools API:
// - Je Zeile höchstens ein Symbol, nach Vorrang: Fehler ✕, Warnung ▲,
//   Hinweis ●, Code-Aktion ◆, überschreibt ↑, wird überschrieben ↓ (Choose).
//   Die Unterschalter (Probleme, Code-Aktionen, Überschreibungen) nehmen
//   ihre Symbole aus der Wahl; die nächste Art rückt nach.
// - ProblemSymbol: schwerstes Problem, das in der Zeile beginnt; inaktive
//   Bereiche und uses-Hinweise zählen nicht.
// - TAtlasFileOverrides.FromJson liest die Antwort von
//   atlas.server.overrideMarks ({"lines": [{"line", "overrides": [...],
//   "overridden": [...]}]}, Zeilen ab 0); ein Symbol nur, solange die Zeile
//   im Editor noch den Text vom Abruf hat (wie bei den Rekursionssymbolen).
// - Width: Breite der Spalte aus der Zeilenhöhe, damit sie mit Schrift und
//   Skalierung wächst.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Problems.Contract;

type
{$SCOPEDENUMS ON}
  /// <summary>Symbol einer Zeile, nach Vorrang (vorn wichtiger).</summary>
  TAtlasGutterSymbol = (None, Error, Warning, Hint, Action, Overrides, Overridden);
{$SCOPEDENUMS OFF}

  /// <summary>Unterschalter der Spalte (editor.gutterColumn.*).</summary>
  TAtlasGutterColumnOptions = record
    Problems: Boolean;
    CodeActions: Boolean;
    Overrides: Boolean;
    class function All: TAtlasGutterColumnOptions; static;
  end;

  /// <summary>Was in einer Zeile vorliegt.</summary>
  TAtlasGutterLine = record
    Problem: TAtlasGutterSymbol;
    Action: Boolean;
    Overrides: Boolean;
    Overridden: Boolean;
  end;

  TAtlasGutterTarget = record
    /// <summary>Typ und Methode, z. B. "TControl.Paint".</summary>
    Name: string;
    FileName: string;
    /// <summary>0-basiert.</summary>
    Line: Integer;
    Character: Integer;
  end;

  TAtlasGutterOverrides = record
    /// <summary>0-basiert.</summary>
    Line: Integer;
    Overrides: TArray<TAtlasGutterTarget>;
    Overridden: TArray<TAtlasGutterTarget>;
  end;

  TAtlasFileOverrides = record
    Lines: TArray<TAtlasGutterOverrides>;
    /// <summary>Antwort von atlas.server.overrideMarks; AToPath wandelt URIs in Dateinamen. Leer bei unbekanntem
    /// Format.</summary>
    class function FromJson(AValue: TJSONValue; const AToPath: TFunc<string, string>): TAtlasFileOverrides; static;
    /// <summary>Eintrag der Zeile ALine (0-basiert); False ohne.</summary>
    function At(ALine: Integer; out AEntry: TAtlasGutterOverrides): Boolean;
    function HasLines: Boolean;
  end;

  TAtlasGutterColumn = class
  public const
    /// <summary>Breite bei 96 DPI und 16 Pixeln Zeilenhöhe.</summary>
    BaseWidth = 16;
  public
    /// <summary>Symbol der Zeile nach Vorrang und Unterschaltern; None ohne.</summary>
    class function Choose(const ALine: TAtlasGutterLine; const AOptions: TAtlasGutterColumnOptions): TAtlasGutterSymbol;
      static;
    /// <summary>Schwerstes Problem aus AProblems, das in ALine (0-basiert) beginnt; None ohne.</summary>
    class function ProblemSymbol(const AProblems: TArray<TAtlasProblem>; ALine: Integer): TAtlasGutterSymbol; static;
    /// <summary>Probleme aus AProblems, die in ALine beginnen, schwerste zuerst (für die Tafel).</summary>
    class function ProblemsAt(const AProblems: TArray<TAtlasProblem>; ALine: Integer): TArray<TAtlasProblem>; static;
    /// <summary>Zeichen des Symbols für Tafel und Barrierefreiheit; '' bei None.</summary>
    class function Glyph(ASymbol: TAtlasGutterSymbol): string; static;
    /// <summary>Breite der Spalte in Pixeln für die Zeilenhöhe ALineHeight: so breit wie hoch, mindestens 12.
    /// </summary>
    class function Width(ALineHeight: Integer): Integer; static;
    /// <summary>Überschrift der Tafel eines Problems: Code und Schweregrad, z. B. "E2003 · Fehler"; ASeverity
    /// ist der Text des Schweregrads.</summary>
    class function ProblemTitle(const AProblem: TAtlasProblem; const ASeverity: string): string; static;
    /// <summary>Text eines Sprungziels: "TControl.Paint — Controls.pas:30" (Zeile ab 1).</summary>
    class function TargetText(const ATarget: TAtlasGutterTarget): string; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.Math;

{ TAtlasGutterColumnOptions }

class function TAtlasGutterColumnOptions.All: TAtlasGutterColumnOptions;
begin
  Result.Problems := True;
  Result.CodeActions := True;
  Result.Overrides := True;
end;

{ TAtlasFileOverrides }

function TargetsOf(AValue: TJSONValue; const AToPath: TFunc<string, string>): TArray<TAtlasGutterTarget>;
var
  Item: TJSONValue;
  Target: TAtlasGutterTarget;
  Uri: string;
begin
  Result := nil;
  if not (AValue is TJSONArray) then
    Exit;
  for Item in TJSONArray(AValue) do
  begin
    if not (Item is TJSONObject) then
      Continue;
    Target := Default(TAtlasGutterTarget);
    Target.Name := TJSONObject(Item).GetValue<string>('name', '');
    Uri := TJSONObject(Item).GetValue<string>('uri', '');
    Target.FileName := Uri;
    if Assigned(AToPath) and (Uri <> '') then
      Target.FileName := AToPath(Uri);
    Target.Line := TJSONObject(Item).GetValue<Integer>('line', -1);
    Target.Character := TJSONObject(Item).GetValue<Integer>('character', 0);
    if (Target.Name <> '') and (Target.FileName <> '') and (Target.Line >= 0) then
      Result := Result + [Target];
  end;
end;

class function TAtlasFileOverrides.FromJson(AValue: TJSONValue;
  const AToPath: TFunc<string, string>): TAtlasFileOverrides;
var
  Item: TJSONValue;
  Entry: TAtlasGutterOverrides;
begin
  Result := Default(TAtlasFileOverrides);
  // Typen selbst prüfen: GetValue<TJSONArray> wandelt eine Zahl ungeprüft um.
  if not (AValue is TJSONObject) or not (TJSONObject(AValue).GetValue('lines') is TJSONArray) then
    Exit;
  for Item in TJSONArray(TJSONObject(AValue).GetValue('lines')) do
  begin
    if not (Item is TJSONObject) then
      Continue;
    Entry := Default(TAtlasGutterOverrides);
    Entry.Line := TJSONObject(Item).GetValue<Integer>('line', -1);
    Entry.Overrides := TargetsOf(TJSONObject(Item).GetValue('overrides'), AToPath);
    Entry.Overridden := TargetsOf(TJSONObject(Item).GetValue('overridden'), AToPath);
    if (Entry.Line >= 0) and ((Length(Entry.Overrides) > 0) or (Length(Entry.Overridden) > 0)) then
      Result.Lines := Result.Lines + [Entry];
  end;
end;

function TAtlasFileOverrides.At(ALine: Integer; out AEntry: TAtlasGutterOverrides): Boolean;
var
  Entry: TAtlasGutterOverrides;
begin
  AEntry := Default(TAtlasGutterOverrides);
  for Entry in Lines do
    if Entry.Line = ALine then
    begin
      AEntry := Entry;
      Exit(True);
    end;
  Result := False;
end;

function TAtlasFileOverrides.HasLines: Boolean;
begin
  Result := Length(Lines) > 0;
end;

{ TAtlasGutterColumn }

class function TAtlasGutterColumn.Choose(const ALine: TAtlasGutterLine;
  const AOptions: TAtlasGutterColumnOptions): TAtlasGutterSymbol;
begin
  Result := TAtlasGutterSymbol.None;
  if AOptions.Problems and (ALine.Problem in [TAtlasGutterSymbol.Error, TAtlasGutterSymbol.Warning,
    TAtlasGutterSymbol.Hint]) then
    Result := ALine.Problem
  else if AOptions.CodeActions and ALine.Action then
    Result := TAtlasGutterSymbol.Action
  else if AOptions.Overrides and ALine.Overrides then
    Result := TAtlasGutterSymbol.Overrides
  else if AOptions.Overrides and ALine.Overridden then
    Result := TAtlasGutterSymbol.Overridden;
end;

function Counts(const AProblem: TAtlasProblem; ALine: Integer): Boolean;
begin
  Result := (AProblem.StartLine = ALine) and not AProblem.Unnecessary and (AProblem.UsesUnit = '');
end;

function SymbolOf(ASeverity: TAtlasProblemSeverity): TAtlasGutterSymbol;
begin
  case ASeverity of
    TAtlasProblemSeverity.Error:
      Result := TAtlasGutterSymbol.Error;
    TAtlasProblemSeverity.Warning:
      Result := TAtlasGutterSymbol.Warning;
  else
    Result := TAtlasGutterSymbol.Hint;
  end;
end;

class function TAtlasGutterColumn.ProblemSymbol(const AProblems: TArray<TAtlasProblem>;
  ALine: Integer): TAtlasGutterSymbol;
var
  Problem: TAtlasProblem;
  Symbol: TAtlasGutterSymbol;
begin
  Result := TAtlasGutterSymbol.None;
  for Problem in AProblems do
    if Counts(Problem, ALine) then
    begin
      Symbol := SymbolOf(Problem.Severity);
      if (Result = TAtlasGutterSymbol.None) or (Ord(Symbol) < Ord(Result)) then
        Result := Symbol;
    end;
end;

class function TAtlasGutterColumn.ProblemsAt(const AProblems: TArray<TAtlasProblem>;
  ALine: Integer): TArray<TAtlasProblem>;
var
  Problem: TAtlasProblem;
  Index, Position: Integer;
begin
  Result := nil;
  for Problem in AProblems do
    if Counts(Problem, ALine) then
    begin
      // Stabil nach Schweregrad: Gleich schwere behalten die Reihenfolge des Servers.
      Position := Length(Result);
      for Index := 0 to High(Result) do
        if Ord(Problem.Severity) < Ord(Result[Index].Severity) then
        begin
          Position := Index;
          Break;
        end;
      Insert(Problem, Result, Position);
    end;
end;

class function TAtlasGutterColumn.Glyph(ASymbol: TAtlasGutterSymbol): string;
begin
  case ASymbol of
    TAtlasGutterSymbol.Error:
      Result := '✕';
    TAtlasGutterSymbol.Warning:
      Result := '▲';
    TAtlasGutterSymbol.Hint:
      Result := '●';
    TAtlasGutterSymbol.Action:
      Result := '◆';
    TAtlasGutterSymbol.Overrides:
      Result := '↑';
    TAtlasGutterSymbol.Overridden:
      Result := '↓';
  else
    Result := '';
  end;
end;

class function TAtlasGutterColumn.Width(ALineHeight: Integer): Integer;
begin
  Result := Max(12, ALineHeight);
end;

class function TAtlasGutterColumn.ProblemTitle(const AProblem: TAtlasProblem; const ASeverity: string): string;
begin
  Result := ASeverity;
  if AProblem.Code <> '' then
    Result := AProblem.Code + ' · ' + ASeverity;
end;

class function TAtlasGutterColumn.TargetText(const ATarget: TAtlasGutterTarget): string;
begin
  Result := Format('%s — %s:%d', [ATarget.Name, ExtractFileName(ATarget.FileName), ATarget.Line + 1]);
end;

end.
