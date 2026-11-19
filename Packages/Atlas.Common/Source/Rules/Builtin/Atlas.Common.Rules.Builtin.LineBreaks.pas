unit Atlas.Common.Rules.Builtin.LineBreaks;

// Regel line-break-split-replace (#2095): Eine Routine ersetzt #13 und #10 in zwei getrennten Aufrufen
// (StringReplace, ReplaceStr, ReplaceText, .Replace), ohne vorher #13#10 bzw. sLineBreak zu ersetzen. Aus einem
// Windows-Zeilenende #13#10 werden so zwei Zeichen (zwei Leerzeichen statt einem). Unter Linux mit #10 als
// sLineBreak fällt das in Tests nicht auf. Still, wenn das erste Ersetzen #13 entfernt oder durch #10 ersetzt bzw.
// wenn das zweite #13 entfernt: Dann bleibt aus #13#10 genau ein Zeichen.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  cLineBreakSplitReplaceRuleId = 'line-break-split-replace';

type
  TLineBreakSplitReplaceRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

/// <summary>Meldet die Regel in ARegistry an.</summary>
procedure RegisterLineBreakRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TLineBreakText = (Title, Message);

  /// <summary>Was ein Argument eines Ersetzens darstellt.</summary>
  TBreakChar = (Other, Empty, CarriageReturn, LineFeed, Both);

const
  cTexts: array[TLineBreakText] of TAtlasText = (
    (De: '#13 und #10 getrennt ersetzt'; En: '#13 and #10 replaced separately'),
    (De: '#13 und #10 werden einzeln ersetzt (Zeile %d und hier): Aus einem Windows-Zeilenende #13#10 werden zwei ' +
      'Zeichen. Zuerst #13#10 (sLineBreak) ersetzen, dann die einzelnen.';
     En: '#13 and #10 are replaced one by one (line %d and here): a Windows line break #13#10 turns into two ' +
      'characters. Replace #13#10 (sLineBreak) first, then the single ones.'));

{$SCOPEDENUMS OFF}

const
  cTextFirstRoutines: array[0..2] of string = ('StringReplace', 'ReplaceStr', 'ReplaceText');

type
  /// <summary>Ein Ersetzen in der Routine: was ersetzt wird und wodurch.</summary>
  TReplaceCall = record
    Node: TSyntaxNode;
    Search: TBreakChar;
    Replacement: TBreakChar;
  end;

/// <summary>Literal oder Name ANode als Zeilenende-Zeichen.</summary>
function BreakCharOf(ANode: TSyntaxNode): TBreakChar;
var
  mText: string;
begin
  Result := TBreakChar.Other;
  if (ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, 'sLineBreak') then
  begin
    Exit(TBreakChar.Both);
  end;
  if ANode.Kind <> TSyntaxKind.Literal then
  begin
    Exit;
  end;
  mText := UpperCase(Trim(ANode.Name));
  if mText = '''''' then
  begin
    Result := TBreakChar.Empty;
  end
  else if MatchStr(mText, ['#13', '#$D', '#$0D']) then
  begin
    Result := TBreakChar.CarriageReturn;
  end
  else if MatchStr(mText, ['#10', '#$A', '#$0A']) then
  begin
    Result := TBreakChar.LineFeed;
  end
  else if MatchStr(mText, ['#13#10', '#$D#$A', '#$0D#$0A']) then
  begin
    Result := TBreakChar.Both;
  end;
end;

/// <summary>Ist ANode ein Ersetzen? Dann Such- und Ersatzargument in ACall.</summary>
function ReplaceOf(ANode: TSyntaxNode; out ACall: TReplaceCall): Boolean;
var
  mCallee: TSyntaxNode;
  mFirst: Integer;
begin
  Result := False;
  ACall := Default(TReplaceCall);
  if (ANode.Kind <> TSyntaxKind.Call) or (ANode.ChildCount < 3) then
  begin
    Exit;
  end;
  mCallee := ANode[0];
  if (mCallee.Kind = TSyntaxKind.Identifier) and MatchText(mCallee.Name, cTextFirstRoutines) and
    (ANode.ChildCount >= 4) then
  begin
    mFirst := 2;
  end
  else if (mCallee.Kind = TSyntaxKind.MemberAccess) and SameText(mCallee.Name, 'Replace') then
  begin
    mFirst := 1;
  end
  else
  begin
    Exit;
  end;
  ACall.Node := ANode;
  ACall.Search := BreakCharOf(ANode[mFirst]);
  ACall.Replacement := BreakCharOf(ANode[mFirst + 1]);
  Result := ACall.Search in [TBreakChar.CarriageReturn, TBreakChar.LineFeed, TBreakChar.Both];
end;

/// <summary>Bleibt aus #13#10 nach AFirst und dann ASecond genau ein Zeichen?</summary>
function KeepsOneChar(const AFirst, ASecond: TReplaceCall): Boolean;
begin
  if AFirst.Search = TBreakChar.CarriageReturn then
  begin
    Result := AFirst.Replacement in [TBreakChar.Empty, TBreakChar.LineFeed];
  end
  else
  begin
    Result := ASecond.Replacement = TBreakChar.Empty;
  end;
end;

/// <summary>Ersetzen in der Routine ARoutine (ohne verschachtelte Routinen und anonyme Methoden) in der Reihenfolge,
/// in der sie laufen: nach dem Ende des Aufrufs (A.Replace(…).Replace(…) zuerst innen).</summary>
function CallsOf(ARoutine: TSyntaxNode): TArray<TReplaceCall>;
var
  mCalls: TList<TReplaceCall>;
begin
  mCalls := TList<TReplaceCall>.Create;
  try
    ARoutine.Walk(
      function(ANode: TSyntaxNode): Boolean
      var
        mCall: TReplaceCall;
      begin
        Result := (ANode = ARoutine) or not (ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]);
        if Result and ReplaceOf(ANode, mCall) then
        begin
          mCalls.Add(mCall);
        end;
      end);
    mCalls.Sort(TComparer<TReplaceCall>.Construct(
      function(const ALeft, ARight: TReplaceCall): Integer
      begin
        Result := ALeft.Node.EndOffset - ARight.Node.EndOffset;
      end));
    Result := mCalls.ToArray;
  finally
    mCalls.Free;
  end;
end;

/// <summary>Meldet in ARoutine das zweite der getrennten Ersetzen.</summary>
procedure CheckRoutine(ARoutine: TSyntaxNode; const AReport: IRuleReport);
var
  mCalls: TArray<TReplaceCall>;
  mIndex, mFirst: Integer;
begin
  mCalls := CallsOf(ARoutine);
  mFirst := -1;
  for mIndex := 0 to High(mCalls) do
  begin
    case mCalls[mIndex].Search of
      TBreakChar.Both:
        // Danach sind keine Paare mehr übrig.
        Exit;
      TBreakChar.CarriageReturn, TBreakChar.LineFeed:
        if mFirst < 0 then
        begin
          mFirst := mIndex;
        end
        else if mCalls[mIndex].Search <> mCalls[mFirst].Search then
        begin
          if not KeepsOneChar(mCalls[mFirst], mCalls[mIndex]) then
          begin
            AReport.Add(TTextRange.Create(mCalls[mIndex].Node.StartPos, mCalls[mIndex].Node.EndPos),
              cTexts[TLineBreakText.Message].Fmt([mCalls[mFirst].Node.StartPos.Line + 1]), TRuleConfidence.High);
          end;
          Exit;
        end;
    else
      // Andere Suchtexte sind oben ausgeschieden.
    end;
  end;
end;

{ TLineBreakSplitReplaceRule }

function TLineBreakSplitReplaceRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cLineBreakSplitReplaceRuleId, TRuleSeverity.Warning,
    cTexts[TLineBreakText.Title].Text);
end;

procedure TLineBreakSplitReplaceRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'Replace') then
  begin
    Exit;
  end;
  AContext.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := True;
      if ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
      begin
        CheckRoutine(ANode, AReport);
      end;
    end);
end;

procedure RegisterLineBreakRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TLineBreakSplitReplaceRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.LineBreaks', cTexts);

end.
