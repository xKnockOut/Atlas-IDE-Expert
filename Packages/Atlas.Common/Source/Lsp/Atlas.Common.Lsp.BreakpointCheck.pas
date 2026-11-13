unit Atlas.Common.Lsp.BreakpointCheck;

// Haltepunkte, die nicht greifen werden (#577), Teil des Servers: Das Plugin
// schickt vor dem Start einer Debug-Sitzung (oder mit dem Befehl „Haltepunkte
// prüfen“) die Zeilen seiner aktiven Quelltext-Haltepunkte je Datei, der
// Server ordnet jede Zeile ein:
//   - inactive: Die Zeile liegt in einem Zweig der bedingten Kompilierung, der
//     unter den Symbolen des Projekts nicht gilt ({$IFDEF RELEASE} beim
//     Debug-Build); detail nennt die Bedingung.
//   - noDebugInfo: An der Zeile gilt {$D-} bzw. {$DEBUGINFO OFF}, aus der
//     Unit oder aus den Projektoptionen (DCC_DebugInformation); detail nennt
//     die Herkunft.
//   - noCode: Die Zeile trägt keinen ausführbaren Code (Kommentar, Leerzeile,
//     Deklaration, var-Abschnitt, else, Fortsetzungszeile einer Anweisung);
//     nextLine nennt die nächste Zeile mit Code in derselben Routine bzw.
//     demselben Block (-1 ohne).
//   - Zeilen, die greifen, stehen nicht in der Antwort.
// Ausführbar ist eine Zeile, auf der eine Anweisung beginnt, das begin und das
// end eines Routinen- oder Programmrumpfs, die Zeile mit until einer
// repeat-Schleife und jede Zeile im Inneren eines asm-Blocks. Das entspricht
// den Zeilen, für die der Compiler Zeileninformation schreibt (blaue Punkte im
// Rand der IDE).
// Befehl:
//   atlas.server.breakpointCheck, Argumente [[{"uri": …, "lines": [12, 40]}, …]]
//   (Zeilen ab 0). Antwort:
//     {"format": 1, "files": [{"uri": …, "items": [{"line": 12, "reason":
//      "noCode", "nextLine": 14}, {"line": 40, "reason": "inactive", "detail":
//      "RELEASE"}]}]}
//   Dateien ohne Befund fehlen; nicht lesbare Dateien stehen mit
//   "unreadable": true darin.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Pascal.CompilerSwitches;

type
  {$SCOPEDENUMS ON}
  TLspBreakpointReason = (Ok, NoCode, Inactive, NoDebugInfo);
  {$SCOPEDENUMS OFF}

  TLspBreakpointVerdict = record
    /// <summary>Zeile ab 0.</summary>
    Line: Integer;
    Reason: TLspBreakpointReason;
    /// <summary>Bedingung des inaktiven Zweigs bzw. Herkunft von $D-; '' sonst.</summary>
    Detail: string;
    /// <summary>Bei NoCode die nächste Zeile mit Code (ab 0); -1 ohne.</summary>
    NextLine: Integer;
  end;

  TLspBreakpointVerdicts = TArray<TLspBreakpointVerdict>;

  /// <summary>Eine Datei der Anfrage: URI und Zeilen ab 0.</summary>
  TLspBreakpointFile = record
    Uri: string;
    Lines: TArray<Integer>;
  end;

  TLspBreakpointCheck = class
  public const
    cCommand = 'atlas.server.breakpointCheck';
    cReasonNames: array[TLspBreakpointReason] of string = ('ok', 'noCode', 'inactive', 'noDebugInfo');
  private
    class procedure AddLine(var ALines: TArray<Boolean>; ALine: Integer); static;
    class procedure AddNode(var ALines: TArray<Boolean>; ANode: TSyntaxNode); static;
    class function InactiveCondition(const AProcessed: TPreprocessorResult; ALine: Integer;
      out ACondition: string): Boolean; static;
    class function DebugInfoOff(const AProcessed: TPreprocessorResult; ALine: Integer;
      const AInput: TCompilerSwitchInput; out AOrigin: string): Boolean; static;
    class function NextCodeLine(const ALines: TArray<Boolean>; ATree: TSyntaxTree; ALine: Integer): Integer; static;
    class function EnclosingBody(ATree: TSyntaxTree; ALine: Integer): TSyntaxNode; static;
  public
    /// <summary>Je Zeile der Datei (Index ab 0): trägt sie ausführbaren Code? Länge = letzte Zeile mit Code + 1.
    /// </summary>
    class function CodeLines(ATree: TSyntaxTree): TArray<Boolean>; static;
    /// <summary>Einordnung von ALines. ATree ist aus den aktiven Zweigen gelesen, AProcessed ein voller Lauf des
    /// Präprozessors über denselben Text (TPascalPreprocessor.Process, auch ohne Bedingungen: daraus kommen die
    /// Direktiven für $D); AInput trägt Symbole und Eigenschaften des Projekts. Zeilen, die greifen, haben Reason
    /// Ok.</summary>
    class function Check(ATree: TSyntaxTree; const AProcessed: TPreprocessorResult;
      const AInput: TCompilerSwitchInput; const ALines: TArray<Integer>): TLspBreakpointVerdicts; static;
    /// <summary>Dateien aus dem ersten Argument; ungültige Einträge fallen weg.</summary>
    class function ReadFiles(AArguments: TJSONArray): TArray<TLspBreakpointFile>; static;
    /// <summary>Eintrag einer Datei für "files"; nil, wenn alle Zeilen greifen.</summary>
    class function FileToJson(const AUri: string; const AVerdicts: TLspBreakpointVerdicts): TJSONObject; static;
    /// <summary>Eintrag einer nicht lesbaren Datei.</summary>
    class function UnreadableToJson(const AUri: string): TJSONObject; static;
    /// <summary>Antwort mit den Einträgen AFiles (übernimmt sie).</summary>
    class function AnswerToJson(const AFiles: TArray<TJSONObject>): TJSONObject; static;
  end;

implementation

uses
  System.Math,
  Atlas.Text.Lines;

const
  cFormat = 1;

{ TLspBreakpointCheck }

class procedure TLspBreakpointCheck.AddLine(var ALines: TArray<Boolean>; ALine: Integer);
var
  mOld, mIndex: Integer;
begin
  if ALine < 0 then
  begin
    Exit;
  end;
  if ALine >= Length(ALines) then
  begin
    mOld := Length(ALines);
    SetLength(ALines, ALine + 1);
    for mIndex := mOld to ALine do
    begin
      ALines[mIndex] := False;
    end;
  end;
  ALines[ALine] := True;
end;

function IsStatement(AKind: TSyntaxKind): Boolean;
begin
  case AKind of
    TSyntaxKind.AssignStatement, TSyntaxKind.CallStatement, TSyntaxKind.IfStatement, TSyntaxKind.CaseStatement,
    TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement,
    TSyntaxKind.WithStatement, TSyntaxKind.TryStatement, TSyntaxKind.RaiseStatement, TSyntaxKind.GotoStatement,
    TSyntaxKind.InlineVar, TSyntaxKind.InlineConst:
      Result := True;
  else
    Result := False;
  end;
end;

/// <summary>Rumpf einer Routine oder des Hauptprogramms (begin und end tragen Code), nicht ein begin … end als
/// Anweisung.</summary>
function IsBody(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind in [TSyntaxKind.Block, TSyntaxKind.AsmBlock]) and (ANode.Parent <> nil) and
    (ANode.Parent.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.ProgramFile, TSyntaxKind.LibraryFile,
    TSyntaxKind.AnonymousMethod]);
end;

class procedure TLspBreakpointCheck.AddNode(var ALines: TArray<Boolean>; ANode: TSyntaxNode);
var
  mLine: Integer;
begin
  if IsStatement(ANode.Kind) then
  begin
    AddLine(ALines, ANode.StartPos.Line);
    if ANode.Kind = TSyntaxKind.RepeatStatement then
    begin
      // Die Bedingung hinter until wird geprüft; die Zeile mit repeat selbst trägt ebenfalls den Sprung.
      AddLine(ALines, ANode.EndPos.Line);
    end;
  end;
  if IsBody(ANode) then
  begin
    AddLine(ALines, ANode.StartPos.Line);
    AddLine(ALines, ANode.EndPos.Line);
  end;
  if ANode.Kind = TSyntaxKind.AsmBlock then
  begin
    for mLine := ANode.StartPos.Line + 1 to ANode.EndPos.Line - 1 do
    begin
      AddLine(ALines, mLine);
    end;
  end;
end;

class function TLspBreakpointCheck.CodeLines(ATree: TSyntaxTree): TArray<Boolean>;
var
  mLines: TArray<Boolean>;
begin
  mLines := nil;
  if (ATree <> nil) and (ATree.Root <> nil) then
  begin
    ATree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        AddNode(mLines, ANode);
        Result := True;
      end);
  end;
  Result := mLines;
end;

class function TLspBreakpointCheck.InactiveCondition(const AProcessed: TPreprocessorResult; ALine: Integer;
  out ACondition: string): Boolean;
var
  mRange: TInactiveRange;
  mBranch: TConditionalRange;
  mBest: Integer;
begin
  ACondition := '';
  Result := False;
  for mRange in AProcessed.InactiveRanges do
  begin
    // Die Zeile der Direktive selbst ist aktiv; inaktiv ist erst, was dahinter beginnt.
    if (mRange.FileIndex = 0) and (ALine > mRange.Range.StartPos.Line) and (ALine < mRange.Range.EndPos.Line) then
    begin
      Result := True;
      Break;
    end;
  end;
  if not Result then
  begin
    Exit;
  end;
  // Bedingung des innersten nicht geltenden Zweigs, der die Zeile umfasst.
  mBest := MaxInt;
  for mBranch in TPascalPreprocessor.MainConditionals(AProcessed) do
  begin
    if not mBranch.Active and (ALine >= mBranch.Range.StartPos.Line) and (ALine <= mBranch.Range.EndPos.Line) and
      (mBranch.Range.EndPos.Line - mBranch.Range.StartPos.Line < mBest) then
    begin
      mBest := mBranch.Range.EndPos.Line - mBranch.Range.StartPos.Line;
      ACondition := mBranch.Condition;
    end;
  end;
end;

class function TLspBreakpointCheck.DebugInfoOff(const AProcessed: TPreprocessorResult; ALine: Integer;
  const AInput: TCompilerSwitchInput; out AOrigin: string): Boolean;
var
  mState: TCompilerSwitchState;
  mEntry: TSwitchEntry;
begin
  AOrigin := '';
  Result := False;
  mState := TCompilerSwitches.At(AProcessed, TTextPosition.Create(ALine, 0), AInput);
  for mEntry in mState.Switches do
  begin
    if SameText(mEntry.Name, 'D') then
    begin
      Result := (mEntry.Value = '-') or SameText(mEntry.Value, 'OFF');
      if Result then
      begin
        AOrigin := mEntry.Origin.Text;
        if mEntry.Origin.Line >= 0 then
        begin
          AOrigin := Format('%s (%d)', [AOrigin, mEntry.Origin.Line + 1]);
        end;
      end;
      Exit;
    end;
  end;
end;

class function TLspBreakpointCheck.EnclosingBody(ATree: TSyntaxTree; ALine: Integer): TSyntaxNode;
var
  mBest: TSyntaxNode;
begin
  mBest := nil;
  if (ATree <> nil) and (ATree.Root <> nil) then
  begin
    ATree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := (ANode.StartPos.Line <= ALine) and (ANode.EndPos.Line >= ALine);
        if Result and IsBody(ANode) then
        begin
          mBest := ANode;
        end;
      end);
  end;
  Result := mBest;
end;

class function TLspBreakpointCheck.NextCodeLine(const ALines: TArray<Boolean>; ATree: TSyntaxTree;
  ALine: Integer): Integer;
var
  mBody: TSyntaxNode;
  mLast, mLine: Integer;
begin
  Result := -1;
  mBody := EnclosingBody(ATree, ALine);
  if mBody = nil then
  begin
    // Zwischen den Routinen (Deklarationen, Kommentar vor der Routine): erste Zeile mit Code danach.
    mLast := High(ALines);
  end
  else
  begin
    mLast := Min(mBody.EndPos.Line, High(ALines));
  end;
  for mLine := ALine + 1 to mLast do
  begin
    if ALines[mLine] then
    begin
      Exit(mLine);
    end;
  end;
end;

class function TLspBreakpointCheck.Check(ATree: TSyntaxTree; const AProcessed: TPreprocessorResult;
  const AInput: TCompilerSwitchInput; const ALines: TArray<Integer>): TLspBreakpointVerdicts;
var
  mCode: TArray<Boolean>;
  mIndex: Integer;
  mVerdict: TLspBreakpointVerdict;
begin
  mCode := CodeLines(ATree);
  SetLength(Result, Length(ALines));
  for mIndex := 0 to High(ALines) do
  begin
    mVerdict := Default(TLspBreakpointVerdict);
    mVerdict.Line := ALines[mIndex];
    mVerdict.NextLine := -1;
    mVerdict.Reason := TLspBreakpointReason.Ok;
    // Reihenfolge nach Gewicht: Ein inaktiver Zweig erklärt auch, warum dort kein Code steht.
    if InactiveCondition(AProcessed, mVerdict.Line, mVerdict.Detail) then
    begin
      mVerdict.Reason := TLspBreakpointReason.Inactive;
    end
    else if DebugInfoOff(AProcessed, mVerdict.Line, AInput, mVerdict.Detail) then
    begin
      mVerdict.Reason := TLspBreakpointReason.NoDebugInfo;
    end
    else if (mVerdict.Line < 0) or (mVerdict.Line > High(mCode)) or not mCode[mVerdict.Line] then
    begin
      mVerdict.Reason := TLspBreakpointReason.NoCode;
      mVerdict.NextLine := NextCodeLine(mCode, ATree, mVerdict.Line);
    end;
    Result[mIndex] := mVerdict;
  end;
end;

class function TLspBreakpointCheck.ReadFiles(AArguments: TJSONArray): TArray<TLspBreakpointFile>;
var
  mList, mLines: TJSONArray;
  mItem, mLine: TJSONValue;
  mFile: TLspBreakpointFile;
begin
  Result := nil;
  if (AArguments = nil) or (AArguments.Count < 1) or not (AArguments.Items[0] is TJSONArray) then
  begin
    Exit;
  end;
  mList := TJSONArray(AArguments.Items[0]);
  for mItem in mList do
  begin
    if not (mItem is TJSONObject) then
    begin
      Continue;
    end;
    mFile := Default(TLspBreakpointFile);
    mFile.Uri := TJSONObject(mItem).GetValue<string>('uri', '');
    if (mFile.Uri = '') or not (TJSONObject(mItem).GetValue('lines') is TJSONArray) then
    begin
      Continue;
    end;
    mLines := TJSONArray(TJSONObject(mItem).GetValue('lines'));
    for mLine in mLines do
    begin
      if mLine is TJSONNumber then
      begin
        mFile.Lines := mFile.Lines + [TJSONNumber(mLine).AsInt];
      end;
    end;
    Result := Result + [mFile];
  end;
end;

class function TLspBreakpointCheck.FileToJson(const AUri: string; const AVerdicts: TLspBreakpointVerdicts): TJSONObject;
var
  mItems: TJSONArray;
  mItem: TJSONObject;
  mVerdict: TLspBreakpointVerdict;
begin
  mItems := TJSONArray.Create;
  for mVerdict in AVerdicts do
  begin
    if mVerdict.Reason = TLspBreakpointReason.Ok then
    begin
      Continue;
    end;
    mItem := TJSONObject.Create;
    mItem.AddPair('line', TJSONNumber.Create(mVerdict.Line));
    mItem.AddPair('reason', cReasonNames[mVerdict.Reason]);
    if mVerdict.Detail <> '' then
    begin
      mItem.AddPair('detail', mVerdict.Detail);
    end;
    if mVerdict.Reason = TLspBreakpointReason.NoCode then
    begin
      mItem.AddPair('nextLine', TJSONNumber.Create(mVerdict.NextLine));
    end;
    mItems.AddElement(mItem);
  end;
  if mItems.Count = 0 then
  begin
    mItems.Free;
    Exit(nil);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('uri', AUri);
  Result.AddPair('items', mItems);
end;

class function TLspBreakpointCheck.UnreadableToJson(const AUri: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('uri', AUri);
  Result.AddPair('unreadable', TJSONBool.Create(True));
end;

class function TLspBreakpointCheck.AnswerToJson(const AFiles: TArray<TJSONObject>): TJSONObject;
var
  mFiles: TJSONArray;
  mFile: TJSONObject;
begin
  mFiles := TJSONArray.Create;
  for mFile in AFiles do
  begin
    if mFile <> nil then
    begin
      mFiles.AddElement(mFile);
    end;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('format', TJSONNumber.Create(cFormat));
  Result.AddPair('files', mFiles);
end;

end.
