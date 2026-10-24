unit Atlas.Common.Editing.DisableWarning;

// Compilermeldung gezielt abschalten (#531): Schalter vor und hinter die
// betroffene Stelle setzen.
//   - Warnung mit eigenem Bezeichner: {$WARN SYMBOL_DEPRECATED OFF} …
//     {$WARN SYMBOL_DEPRECATED ON} (Zuordnung in Pascal.WarningCodes).
//   - Hinweis: {$HINTS OFF} … {$HINTS ON}.
//   - Warnung ohne eigenen Bezeichner: {$WARNINGS OFF} … {$WARNINGS ON};
//     das betrifft alle Warnungen dazwischen (AllWarnings).
// Bereiche:
//   - Zeile: Schalter in eigenen Zeilen direkt davor und dahinter, mit der
//     Einrückung der Zeile.
//   - Routine: um die innerste Routine mit Rumpf, die die Zeile enthält, vom
//     Kopf bis zu ihrem end;. Ablaufmeldungen (TWarningCodes.IsRoutineWide)
//     gibt es nur so.
//   - Unit: nur OFF in einer eigenen Zeile hinter dem Kopf (unit X;).
// Eine Begründung kommt als Zeilenkommentar hinter den OFF-Schalter.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  TDisableWarningScope = (Line, Routine, UnitWide);

  TDisableWarningSwitch = record
    /// <summary>Meldungsnummer wie W1000, in Großbuchstaben.</summary>
    Code: string;
    /// <summary>Bezeichner für {$WARN}; '' bei Hinweisen und Warnungen ohne eigenen Bezeichner.</summary>
    Identifier: string;
    Hint: Boolean;
    /// <summary>{$WARNINGS OFF}: betrifft alle Warnungen.</summary>
    AllWarnings: Boolean;
    /// <summary>Nur für die ganze Routine oder Unit wirksam (Ablaufanalyse).</summary>
    RoutineWide: Boolean;
    function OffText: string;
    function OnText: string;
  end;

  TDisableWarning = class
  public
    /// <summary>Schalter für ACode in der Delphi-Version AVersion (BDS-Nummer); False bei Fehlern und
    /// unbekannten Nummern.</summary>
    class function SwitchFor(const ACode, AVersion: string; out ASwitch: TDisableWarningSwitch): Boolean; static;
    /// <summary>Innerste Routine mit Rumpf, die Zeile ALine (ab 0) enthält; nil ohne.</summary>
    class function RoutineAt(ATree: TSyntaxTree; ALine: Integer): TSyntaxNode; static;
    /// <summary>Zeile (ab 0), hinter der der Kopf (unit X; program X; …) endet; -1 ohne Kopf.</summary>
    class function HeaderEndLine(ATree: TSyntaxTree): Integer; static;
    /// <summary>Einfügungen für ASwitch im Bereich AScope um Zeile ALine (ab 0); False, wenn es den Bereich dort
    /// nicht gibt (Zeile außerhalb des Texts, keine Routine, kein Kopf).</summary>
    class function Edits(const AText: string; ATree: TSyntaxTree; ALine: Integer;
      const ASwitch: TDisableWarningSwitch; AScope: TDisableWarningScope; const AReason: string;
      out AEdits: TArray<TTextEdit>): Boolean; static;
    /// <summary>Begründung als einzeiliger Kommentar; '' ohne.</summary>
    class function ReasonComment(const AReason: string): string; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Text.Lines,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.WarningCodes;

{ TDisableWarningSwitch }

function TDisableWarningSwitch.OffText: string;
begin
  if Hint then
    Result := '{$HINTS OFF}'
  else if Identifier <> '' then
    Result := '{$WARN ' + Identifier + ' OFF}'
  else
    Result := '{$WARNINGS OFF}';
end;

function TDisableWarningSwitch.OnText: string;
begin
  if Hint then
    Result := '{$HINTS ON}'
  else if Identifier <> '' then
    Result := '{$WARN ' + Identifier + ' ON}'
  else
    Result := '{$WARNINGS ON}';
end;

{ TDisableWarning }

class function TDisableWarning.SwitchFor(const ACode, AVersion: string; out ASwitch: TDisableWarningSwitch): Boolean;
begin
  ASwitch := Default(TDisableWarningSwitch);
  ASwitch.Code := UpperCase(Trim(ACode));
  case TWarningCodes.KindOf(ASwitch.Code) of
    TWarningCodeKind.Hint:
      ASwitch.Hint := True;
    TWarningCodeKind.Warning:
      begin
        ASwitch.Identifier := TWarningCodes.Identifier(ASwitch.Code, AVersion);
        ASwitch.AllWarnings := ASwitch.Identifier = '';
      end;
  else
    Exit(False);
  end;
  ASwitch.RoutineWide := TWarningCodes.IsRoutineWide(ASwitch.Code);
  Result := True;
end;

class function TDisableWarning.RoutineAt(ATree: TSyntaxTree; ALine: Integer): TSyntaxNode;
var
  Node: TSyntaxNode;
  Index: Integer;
  Descended: Boolean;
begin
  // Von oben nach unten absteigen; die tiefste Routine mit Rumpf (verschachtelte Routinen) gewinnt.
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
    Exit;
  Node := ATree.Root;
  repeat
    Descended := False;
    for Index := 0 to Node.ChildCount - 1 do
      if (Node[Index].StartPos.Line <= ALine) and (ALine <= Node[Index].EndPos.Line) then
      begin
        Node := Node[Index];
        if (Node.Kind = TSyntaxKind.RoutineDecl) and (Node.FindChild(TSyntaxKind.Block) <> nil) then
          Result := Node;
        Descended := True;
        Break;
      end;
  until not Descended;
end;

class function TDisableWarning.HeaderEndLine(ATree: TSyntaxTree): Integer;
var
  Tokens: TArray<TPascalToken>;
  Index: Integer;
  Started: Boolean;
begin
  Result := -1;
  if ATree = nil then
    Exit;
  Tokens := ATree.Tokens;
  Started := False;
  for Index := 0 to High(Tokens) do
  begin
    if Tokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive] then
      Continue;
    if not Started then
    begin
      // Der Kopf muss das erste Wort sein; sonst (Include-Datei, Ausschnitt) gibt es keinen.
      if not MatchText(Tokens[Index].Text, ['unit', 'program', 'library', 'package']) then
        Exit;
      Started := True;
    end
    else if Tokens[Index].IsSymbol(';') then
      Exit(Tokens[Index].EndPos.Line);
  end;
end;

class function TDisableWarning.ReasonComment(const AReason: string): string;
begin
  Result := StringReplace(AReason, #13#10, ' ', [rfReplaceAll]);
  Result := Trim(StringReplace(StringReplace(Result, #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]));
  if Result <> '' then
    Result := ' // ' + Result;
end;

/// <summary>Neue Zeile vor ALine.</summary>
function Before(ALine: Integer; const AText, ALineBreak: string): TTextEdit;
begin
  Result := TTextEdit.Create(TTextRange.Create(ALine, 0, ALine, 0), AText + ALineBreak);
end;

/// <summary>Neue Zeile hinter ALine (Länge ALength); hinter der letzten Zeile ohne Umbruch am Ende.</summary>
function After(ALine, ALength: Integer; const AText, ALineBreak: string): TTextEdit;
begin
  Result := TTextEdit.Create(TTextRange.Create(ALine, ALength, ALine, ALength), ALineBreak + AText);
end;

class function TDisableWarning.Edits(const AText: string; ATree: TSyntaxTree; ALine: Integer;
  const ASwitch: TDisableWarningSwitch; AScope: TDisableWarningScope; const AReason: string;
  out AEdits: TArray<TTextEdit>): Boolean;
var
  Lines: TArray<string>;
  LineBreak, Indent: string;
  Routine: TSyntaxNode;
  First, Last: Integer;
begin
  AEdits := nil;
  Lines := TTextLines.SplitLines(AText, LineBreak);
  Result := (ALine >= 0) and (ALine <= High(Lines));
  if not Result then
    Exit;
  case AScope of
    TDisableWarningScope.UnitWide:
      begin
        First := HeaderEndLine(ATree);
        Result := (First >= 0) and (First <= High(Lines));
        if Result then
          AEdits := [After(First, Length(Lines[First]), ASwitch.OffText + ReasonComment(AReason), LineBreak)];
        Exit;
      end;
    TDisableWarningScope.Routine:
      begin
        Routine := RoutineAt(ATree, ALine);
        Result := Routine <> nil;
        if not Result then
          Exit;
        First := Routine.StartPos.Line;
        Last := Routine.EndPos.Line;
      end;
  else
    First := ALine;
    Last := ALine;
  end;
  Result := Last <= High(Lines);
  if not Result then
    Exit;
  Indent := TTextLines.IndentOf(Lines[First]);
  AEdits := [Before(First, Indent + ASwitch.OffText + ReasonComment(AReason), LineBreak),
    After(Last, Length(Lines[Last]), Indent + ASwitch.OnText, LineBreak)];
end;

end.
