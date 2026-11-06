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

  /// <summary>Was abgeschaltet wird, in welchem Bereich und mit welcher Begründung.</summary>
  TDisableWarningRequest = record
    Switch: TDisableWarningSwitch;
    Scope: TDisableWarningScope;
    /// <summary>Begründung für den Kommentar; '' ohne.</summary>
    Reason: string;
    class function Create(const ASwitch: TDisableWarningSwitch; AScope: TDisableWarningScope;
      const AReason: string): TDisableWarningRequest; static;
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
    /// <summary>Einfügungen für den Schalter von ARequest in seinem Bereich um Zeile ALine (ab 0); False, wenn es
    /// den Bereich dort nicht gibt (Zeile außerhalb des Texts, keine Routine, kein Kopf).</summary>
    class function Edits(const AText: string; ATree: TSyntaxTree; ALine: Integer;
      const ARequest: TDisableWarningRequest; out AEdits: TArray<TTextEdit>): Boolean; static;
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
  begin
    Result := '{$HINTS OFF}';
  end
  else if Identifier <> '' then
  begin
    Result := '{$WARN ' + Identifier + ' OFF}';
  end
  else
  begin
    Result := '{$WARNINGS OFF}';
  end;
end;

function TDisableWarningSwitch.OnText: string;
begin
  if Hint then
  begin
    Result := '{$HINTS ON}';
  end
  else if Identifier <> '' then
  begin
    Result := '{$WARN ' + Identifier + ' ON}';
  end
  else
  begin
    Result := '{$WARNINGS ON}';
  end;
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
  mNode: TSyntaxNode;
  mIndex: Integer;
  mDescended: Boolean;
begin
  // Von oben nach unten absteigen; die tiefste Routine mit Rumpf (verschachtelte Routinen) gewinnt.
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit;
  end;
  mNode := ATree.Root;
  repeat
    mDescended := False;
    for mIndex := 0 to mNode.ChildCount - 1 do
    begin
      if (mNode[mIndex].StartPos.Line <= ALine) and (ALine <= mNode[mIndex].EndPos.Line) then
      begin
        mNode := mNode[mIndex];
        if (mNode.Kind = TSyntaxKind.RoutineDecl) and (mNode.FindChild(TSyntaxKind.Block) <> nil) then
        begin
          Result := mNode;
        end;
        mDescended := True;
        Break;
      end;
    end;
  until not mDescended;
end;

class function TDisableWarning.HeaderEndLine(ATree: TSyntaxTree): Integer;
var
  mTokens: TArray<TPascalToken>;
  mIndex: Integer;
  mStarted: Boolean;
begin
  Result := -1;
  if ATree = nil then
  begin
    Exit;
  end;
  mTokens := ATree.Tokens;
  mStarted := False;
  for mIndex := 0 to High(mTokens) do
  begin
    if mTokens[mIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive] then
    begin
      Continue;
    end;
    if not mStarted then
    begin
      // Der Kopf muss das erste Wort sein; sonst (Include-Datei, Ausschnitt) gibt es keinen.
      if not MatchText(mTokens[mIndex].Text, ['unit', 'program', 'library', 'package']) then
      begin
        Exit;
      end;
      mStarted := True;
    end
    else if mTokens[mIndex].IsSymbol(';') then
    begin
      Exit(mTokens[mIndex].EndPos.Line);
    end;
  end;
end;

class function TDisableWarning.ReasonComment(const AReason: string): string;
begin
  Result := StringReplace(AReason, #13#10, ' ', [rfReplaceAll]);
  Result := Trim(StringReplace(StringReplace(Result, #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]));
  if Result <> '' then
  begin
    Result := ' // ' + Result;
  end;
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

{ TDisableWarningRequest }

class function TDisableWarningRequest.Create(const ASwitch: TDisableWarningSwitch; AScope: TDisableWarningScope;
  const AReason: string): TDisableWarningRequest;
begin
  Result.Switch := ASwitch;
  Result.Scope := AScope;
  Result.Reason := AReason;
end;

class function TDisableWarning.Edits(const AText: string; ATree: TSyntaxTree; ALine: Integer;
  const ARequest: TDisableWarningRequest; out AEdits: TArray<TTextEdit>): Boolean;
var
  mLines: TArray<string>;
  mLineBreak, mIndent: string;
  mRoutine: TSyntaxNode;
  mFirst, mLast: Integer;
begin
  AEdits := nil;
  mLines := TTextLines.SplitLines(AText, mLineBreak);
  Result := (ALine >= 0) and (ALine <= High(mLines));
  if not Result then
  begin
    Exit;
  end;
  case ARequest.Scope of
    TDisableWarningScope.UnitWide:
      begin
        mFirst := HeaderEndLine(ATree);
        Result := (mFirst >= 0) and (mFirst <= High(mLines));
        if Result then
        begin
          AEdits := [After(mFirst, Length(mLines[mFirst]), ARequest.Switch.OffText + ReasonComment(ARequest.Reason),
            mLineBreak)];
        end;
        Exit;
      end;
    TDisableWarningScope.Routine:
      begin
        mRoutine := RoutineAt(ATree, ALine);
        Result := mRoutine <> nil;
        if not Result then
        begin
          Exit;
        end;
        mFirst := mRoutine.StartPos.Line;
        mLast := mRoutine.EndPos.Line;
      end;
  else
    mFirst := ALine;
    mLast := ALine;
  end;
  Result := mLast <= High(mLines);
  if not Result then
  begin
    Exit;
  end;
  mIndent := TTextLines.IndentOf(mLines[mFirst]);
  AEdits := [Before(mFirst, mIndent + ARequest.Switch.OffText + ReasonComment(ARequest.Reason), mLineBreak),
    After(mLast, Length(mLines[mLast]), mIndent + ARequest.Switch.OnText, mLineBreak)];
end;

end.
