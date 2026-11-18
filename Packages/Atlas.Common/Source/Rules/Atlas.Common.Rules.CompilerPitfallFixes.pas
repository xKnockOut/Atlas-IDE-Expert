unit Atlas.Common.Rules.CompilerPitfallFixes;

// Sichere Korrekturen aus dem Fallenkatalog der Compilermeldungen (#2621, TCompilerPitfalls): System. vor
// TMonitor., eine Unit ins uses des Abschnitts der Zeile, Exit([...]) als Result := [...]; Exit;. Jede Korrektur
// prüft ihre Voraussetzung am Text und liefert sonst nichts; eine unsichere Korrektur bleibt beim Text des Katalogs.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.CompilerPitfalls;

type
  TCompilerPitfallFixes = class
  public
    /// <summary>Änderungen der sicheren Korrektur von APitfall an Zeile ALine (ab 0) in AText (Baum ATree); False,
    /// wenn die Falle keine hat oder ihre Voraussetzung am Text fehlt.</summary>
    class function Edits(APitfall: TCompilerPitfall; const AText: string; ATree: TSyntaxTree; ALine: Integer;
      out AEdits: TArray<TTextEdit>): Boolean; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Text.Lines,
  Atlas.Text.Chars,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Editing.UsesClause;

const
  cMonitor = 'TMonitor.';
  cSystem = 'System.';
  cExitArray = 'Exit([';

/// <summary>Gehört AChar zu einem (qualifizierten) Namen davor?</summary>
function IsNameChar(AChar: Char): Boolean;
begin
  Result := TTextChars.IsIdentChar(AChar) or (AChar = '.');
end;

/// <summary>TMonitor. ohne Namespace davor: System. einfügen.</summary>
function QualifyMonitor(const ALineText: string; ALine: Integer; out AEdits: TArray<TTextEdit>): Boolean;
var
  mStart: Integer;
begin
  AEdits := nil;
  mStart := Pos(cMonitor, ALineText);
  while mStart > 0 do
  begin
    if (mStart = 1) or not IsNameChar(ALineText[mStart - 1]) then
    begin
      AEdits := AEdits + [TTextEdit.Create(TTextRange.Create(ALine, mStart - 1, ALine, mStart - 1), cSystem)];
    end;
    mStart := PosEx(cMonitor, ALineText, mStart + 1);
  end;
  Result := AEdits <> nil;
end;

/// <summary>AUnit ins uses des Abschnitts der Zeile ALine, wenn sie noch fehlt.</summary>
function AddUses(const AText: string; ATree: TSyntaxTree; ALine: Integer; const AUnit: string;
  out AEdits: TArray<TTextEdit>): Boolean;
var
  mEdit: TTextEdit;
begin
  AEdits := nil;
  Result := (ATree <> nil) and (AUnit <> '') and
    not TUsesClauses.IsUsed(TUsesClauses.UsedUnits(ATree.Tokens), AUnit, nil) and
    TUsesClauses.AddUnit(ATree.Tokens, TLineTable.Build(AText).LineStart(ALine), AUnit, TTextLines.LineBreakOf(AText),
    mEdit);
  if Result then
  begin
    AEdits := [mEdit];
  end;
end;

/// <summary>Endet die letzte nicht leere Zeile vor ALine so, dass dort eine neue Anweisung beginnen darf (";" oder
/// begin)? Nach then, else oder do würde aus einer Anweisung zwei.</summary>
function StatementMayStart(const ALines: TArray<string>; ALine: Integer): Boolean;
var
  mIndex: Integer;
  mText: string;
begin
  for mIndex := ALine - 1 downto 0 do
  begin
    mText := Trim(ALines[mIndex]);
    if mText <> '' then
    begin
      Exit(EndsStr(';', mText) or SameText(mText, 'begin') or EndsText(' begin', mText));
    end;
  end;
  Result := False;
end;

/// <summary>Zeile "Exit([...]);" allein: "Result := [...];" und "Exit;" darunter.</summary>
function SplitExit(const AText: string; ALine: Integer; out AEdits: TArray<TTextEdit>): Boolean;
var
  mLines: TArray<string>;
  mLineBreak, mTrimmed, mIndent, mValue: string;
begin
  AEdits := nil;
  mLines := TTextLines.SplitLines(AText, mLineBreak);
  Result := False;
  if (ALine < 0) or (ALine > High(mLines)) then
  begin
    Exit;
  end;
  mTrimmed := Trim(mLines[ALine]);
  mValue := Copy(mTrimmed, Length(cExitArray), Length(mTrimmed) - Length(cExitArray) - 1);
  if not StartsText(cExitArray, mTrimmed) or not EndsStr(']', mValue) or not EndsStr(');', mTrimmed) or
    not StatementMayStart(mLines, ALine) then
  begin
    Exit;
  end;
  mIndent := TTextLines.IndentOf(mLines[ALine]);
  AEdits := [TTextEdit.Create(TTextRange.Create(ALine, 0, ALine, Length(mLines[ALine])),
    mIndent + 'Result := ' + mValue + ';' + mLineBreak + mIndent + 'Exit;')];
  Result := True;
end;

{ TCompilerPitfallFixes }

class function TCompilerPitfallFixes.Edits(APitfall: TCompilerPitfall; const AText: string; ATree: TSyntaxTree;
  ALine: Integer; out AEdits: TArray<TTextEdit>): Boolean;
var
  mInfo: TCompilerPitfallInfo;
begin
  AEdits := nil;
  Result := False;
  if ALine < 0 then
  begin
    Exit;
  end;
  mInfo := TCompilerPitfalls.Info(APitfall, TAtlasLocale.Language);
  case mInfo.FixKind of
    TPitfallFix.QualifySystemMonitor:
      Result := QualifyMonitor(TTextLines.LineAt(TTextLines.SplitLines(AText), ALine), ALine, AEdits);
    TPitfallFix.AddUses:
      Result := AddUses(AText, ATree, ALine, mInfo.UsesUnit, AEdits);
    TPitfallFix.ExitArrayLiteral:
      Result := SplitExit(AText, ALine, AEdits);
  end;
end;

end.
