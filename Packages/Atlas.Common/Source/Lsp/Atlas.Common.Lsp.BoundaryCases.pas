unit Atlas.Common.Lsp.BoundaryCases;

// Grenzfälle als Testfälle (#2173) für Plugin und MCP. Logik in Atlas.Common.Editing.BoundaryCases; den Text
// (offenes Dokument vor der Platte) liefert die Shell.
//
// Befehl atlas.server.boundaryCases [uri, zeile, max?]: zeile 0-basiert irgendwo in der Routine (bei
// verschachtelten gewinnt die innerste), max 1 bis 200 (Vorgabe 20).
// Antwort: null ohne Routine mit Rumpf an der Zeile, sonst
//   { uri, routine, resultType, line, truncated,
//     parameters: [{name, type, kind, neutral}],     kind: unknown, text, ordinal, float, logical, enum, reference
//     cases: [{parameter, value, reason, line, testCase, values: [..]}] }
// line der Fälle 0-basiert, -1 ohne eigene Bedingung; testCase False, wenn der Wert nicht in ein [TestCase]
// passt (nil eines Objekts oder Interfaces); values sind die Werte aller Parameter für den Fall.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Lsp.Commands,
  Atlas.Common.Lsp.TestCases,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.BoundaryCases;

type
  /// <summary>Anfrage des MCP-Werkzeugs suggest_test_cases.</summary>
  TLspBoundaryRequest = record
    /// <summary>Datei für Überschrift bzw. uri.</summary>
    FileName: string;
    /// <summary>Zeile (0-basiert) in der Routine; kleiner 0: Routine nach Namen.</summary>
    Line: Integer;
    /// <summary>"TFoo.Bar" oder "Bar".</summary>
    Routine: string;
    /// <summary>Höchstzahl der Fälle; 0 die Vorgabe.</summary>
    Max: Integer;
    Json: Boolean;
  end;

  TLspBoundaryCases = class
  public const
    cCommand = 'atlas.server.boundaryCases';
    cMinMax = 1;
    cMaxMax = 200;
    cKindNames: array[TBoundaryKind] of string = ('unknown', 'text', 'ordinal', 'float', 'logical', 'enum',
      'reference');
  public
    /// <summary>Meldet den Befehl an (nebenläufig: liest nur).</summary>
    class procedure Attach(ACommands: TLspCommands; const AReadText: TLspTestCasesReadText); static;
    /// <summary>Routine mit Rumpf an Zeile ALine (0-basiert) oder, wenn ALine kleiner 0 ist, mit Namen AName
    /// ("TFoo.Bar" oder "Bar"); nil, wenn es keine gibt.</summary>
    class function RoutineOf(ATree: TSyntaxTree; ALine: Integer; const AName: string): TSyntaxNode; static;
    /// <summary>Lässt sich der Fall als [TestCase] schreiben?</summary>
    class function FitsTestCase(const AResult: TBoundaryResult; ACase: Integer): Boolean; static;
    /// <summary>Ergebnis als JSON. Der Aufrufer übernimmt das Objekt.</summary>
    class function ToJson(const AUri: string; ALine: Integer; const AResult: TBoundaryResult): TJSONObject; static;
    /// <summary>Ergebnis als Markdown für MCP; AFile steht in der Überschrift.</summary>
    class function ToMarkdown(const AFile: string; ALine: Integer; const AResult: TBoundaryResult): string; static;
    /// <summary>Höchstzahl der Fälle: AMax auf cMinMax bis cMaxMax begrenzt, 0 die Vorgabe.</summary>
    class function MaxCases(AMax: Integer): Integer; static;
    /// <summary>Bericht für MCP über die Routine der Anfrage im Text AText, als JSON oder Markdown; False ohne
    /// passende Routine.</summary>
    class function Report(const AText: string; const ARequest: TLspBoundaryRequest;
      out AReport: string): Boolean; static;
    /// <summary>Befehl mit dem Text des Dokuments AArguments[0].</summary>
    class function Execute(const AArguments: TJSONArray; const AReadText: TLspTestCasesReadText): TJSONValue; static;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Editing.DisableWarning,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  TLspBoundaryText = (NeedsUriAndLine, NotReadable, Title, Parameters, NoCases, Truncated, Header, NoTestCase);

const
  cTexts: array[TLspBoundaryText] of TAtlasText = (
    (De: '%s braucht URI und Zeile'; En: '%s needs a URI and a line'),
    (De: '%s ist nicht lesbar'; En: '%s cannot be read'),
    (De: '# Grenzfälle von %s (%s, Zeile %d)'; En: '# Boundary cases of %s (%s, line %d)'),
    (De: 'Parameter (neutraler Wert in Klammern): %s'; En: 'Parameters (neutral value in parentheses): %s'),
    (De: 'Keine Grenzfälle: Die Bedingungen der Routine vergleichen keinen Parameter mit einer Konstanten.';
     En: 'No boundary cases: the conditions of the routine compare no parameter with a constant.'),
    (De: 'Gekürzt auf %d Fälle (maxCases).'; En: 'Truncated to %d cases (maxCases).'),
    (De: '| Parameter | Wert | Grund | Zeile | Werte aller Parameter |';
     En: '| Parameter | Value | Reason | Line | Values of all parameters |'),
    (De: '%s (kein [TestCase])'; En: '%s (no [TestCase])'));

{$SCOPEDENUMS OFF}

/// <summary>Routine mit Rumpf namens AName; Name ganz oder hinter dem letzten Punkt.</summary>
function RoutineNamed(ATree: TSyntaxTree; const AName: string): TSyntaxNode;
var
  mFound: TSyntaxNode;
begin
  mFound := nil;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      mName: string;
    begin
      Result := mFound = nil;
      if (mFound <> nil) or (ANode.Kind <> TSyntaxKind.RoutineDecl) or
        (ANode.FindChild(TSyntaxKind.Block) = nil) then
      begin
        Exit;
      end;
      mName := ANode.Name;
      if SameText(mName, AName) or SameText(Copy(mName, LastDelimiter('.', mName) + 1, MaxInt), AName) then
      begin
        mFound := ANode;
      end;
    end);
  Result := mFound;
end;

class function TLspBoundaryCases.RoutineOf(ATree: TSyntaxTree; ALine: Integer; const AName: string): TSyntaxNode;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit;
  end;
  if ALine >= 0 then
  begin
    Result := TDisableWarning.RoutineAt(ATree, ALine);
  end
  else if Trim(AName) <> '' then
  begin
    Result := RoutineNamed(ATree, Trim(AName));
  end;
end;

class function TLspBoundaryCases.FitsTestCase(const AResult: TBoundaryResult; ACase: Integer): Boolean;
begin
  Result := AResult.Parameters[AResult.Cases[ACase].Parameter].Kind <> TBoundaryKind.Reference;
end;

function StringsToJson(const AValues: TArray<string>): TJSONArray;
var
  mValue: string;
begin
  Result := TJSONArray.Create;
  for mValue in AValues do
  begin
    Result.Add(mValue);
  end;
end;

function ParameterToJson(const AParameter: TBoundaryParameter): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', AParameter.Name);
  Result.AddPair('type', AParameter.TypeName);
  Result.AddPair('kind', TLspBoundaryCases.cKindNames[AParameter.Kind]);
  Result.AddPair('neutral', AParameter.Neutral);
end;

function CaseToJson(const AResult: TBoundaryResult; ACase: Integer): TJSONObject;
var
  mCase: TBoundaryCase;
begin
  mCase := AResult.Cases[ACase];
  Result := TJSONObject.Create;
  Result.AddPair('parameter', TJSONNumber.Create(mCase.Parameter));
  Result.AddPair('value', mCase.Value);
  Result.AddPair('reason', mCase.Reason);
  Result.AddPair('line', TJSONNumber.Create(mCase.Line));
  Result.AddPair('testCase', TJSONBool.Create(TLspBoundaryCases.FitsTestCase(AResult, ACase)));
  Result.AddPair('values', StringsToJson(AResult.Values(ACase)));
end;

class function TLspBoundaryCases.ToJson(const AUri: string; ALine: Integer;
  const AResult: TBoundaryResult): TJSONObject;
var
  mParameters, mCases: TJSONArray;
  mParameter: TBoundaryParameter;
  mIndex: Integer;
begin
  Result := TJSONObject.Create;
  Result.AddPair('uri', AUri);
  Result.AddPair('routine', AResult.Routine);
  Result.AddPair('resultType', AResult.ResultType);
  Result.AddPair('line', TJSONNumber.Create(ALine));
  Result.AddPair('truncated', TJSONBool.Create(AResult.Truncated));
  mParameters := TJSONArray.Create;
  Result.AddPair('parameters', mParameters);
  for mParameter in AResult.Parameters do
  begin
    mParameters.AddElement(ParameterToJson(mParameter));
  end;
  mCases := TJSONArray.Create;
  Result.AddPair('cases', mCases);
  for mIndex := 0 to High(AResult.Cases) do
  begin
    mCases.AddElement(CaseToJson(AResult, mIndex));
  end;
end;

/// <summary>Text für eine Zelle einer Markdown-Tabelle.</summary>
function Cell(const AText: string): string;
begin
  Result := '`' + AText.Replace('|', '\|').Replace('`', '''') + '`';
end;

function ParameterList(const AResult: TBoundaryResult): string;
var
  mParts: TArray<string>;
  mParameter: TBoundaryParameter;
begin
  mParts := nil;
  for mParameter in AResult.Parameters do
  begin
    mParts := mParts + [Format('%s: %s (%s)', [mParameter.Name, mParameter.TypeName, mParameter.Neutral])];
  end;
  Result := string.Join(', ', mParts);
end;

function CaseRow(const AResult: TBoundaryResult; ACase: Integer): string;
var
  mCase: TBoundaryCase;
  mLine, mReason: string;
begin
  mCase := AResult.Cases[ACase];
  mLine := '';
  if mCase.Line >= 0 then
  begin
    mLine := IntToStr(mCase.Line + 1);
  end;
  mReason := mCase.Reason;
  if not TLspBoundaryCases.FitsTestCase(AResult, ACase) then
  begin
    mReason := cTexts[TLspBoundaryText.NoTestCase].Fmt([mReason]);
  end;
  Result := Format('| %s | %s | %s | %s | %s |', [AResult.Parameters[mCase.Parameter].Name, Cell(mCase.Value),
    mReason.Replace('|', '\|'), mLine, Cell(string.Join(', ', AResult.Values(ACase)))]);
end;

class function TLspBoundaryCases.ToMarkdown(const AFile: string; ALine: Integer;
  const AResult: TBoundaryResult): string;
var
  mLines: TArray<string>;
  mIndex: Integer;
begin
  mLines := [cTexts[TLspBoundaryText.Title].Fmt([AResult.Routine, AFile, ALine + 1]), '',
    cTexts[TLspBoundaryText.Parameters].Fmt([ParameterList(AResult)]), ''];
  if Length(AResult.Cases) = 0 then
  begin
    mLines := mLines + [cTexts[TLspBoundaryText.NoCases].Text];
  end
  else
  begin
    mLines := mLines + [cTexts[TLspBoundaryText.Header].Text, '|---|---|---|---|---|'];
    for mIndex := 0 to High(AResult.Cases) do
    begin
      mLines := mLines + [CaseRow(AResult, mIndex)];
    end;
  end;
  if AResult.Truncated then
  begin
    mLines := mLines + ['', cTexts[TLspBoundaryText.Truncated].Fmt([Length(AResult.Cases)])];
  end;
  Result := string.Join(sLineBreak, mLines);
end;

class function TLspBoundaryCases.MaxCases(AMax: Integer): Integer;
begin
  Result := TBoundaryCases.cDefaultMax;
  if AMax <> 0 then
  begin
    Result := EnsureRange(AMax, cMinMax, cMaxMax);
  end;
end;

/// <summary>Höchstzahl aus AArguments[2]; Vorgabe ohne Angabe.</summary>
function MaxOf(const AArguments: TJSONArray): Integer;
begin
  Result := TBoundaryCases.cDefaultMax;
  if (AArguments.Count > 2) and (AArguments.Items[2] is TJSONNumber) then
  begin
    Result := EnsureRange(TJSONNumber(AArguments.Items[2]).AsInt, TLspBoundaryCases.cMinMax,
      TLspBoundaryCases.cMaxMax);
  end;
end;

class function TLspBoundaryCases.Report(const AText: string; const ARequest: TLspBoundaryRequest;
  out AReport: string): Boolean;
var
  mTree: TSyntaxTree;
  mRoutine: TSyntaxNode;
  mResult: TBoundaryResult;
  mLine: Integer;
  mJson: TJSONObject;
begin
  AReport := '';
  mTree := TSyntaxTreeCache.Parse(AText);
  try
    mRoutine := RoutineOf(mTree, ARequest.Line, ARequest.Routine);
    Result := mRoutine <> nil;
    if not Result then
    begin
      Exit;
    end;
    mLine := mRoutine.StartPos.Line;
    mResult := TBoundaryCases.Find(mTree, mRoutine, MaxCases(ARequest.Max));
  finally
    mTree.Free;
  end;
  if not ARequest.Json then
  begin
    AReport := ToMarkdown(ARequest.FileName, mLine, mResult);
    Exit;
  end;
  mJson := ToJson(ARequest.FileName, mLine, mResult);
  try
    AReport := mJson.ToJSON([]);
  finally
    mJson.Free;
  end;
end;

class function TLspBoundaryCases.Execute(const AArguments: TJSONArray;
  const AReadText: TLspTestCasesReadText): TJSONValue;
var
  mUri, mText: string;
  mTree: TSyntaxTree;
  mRoutine: TSyntaxNode;
begin
  if (AArguments = nil) or (AArguments.Count < 2) or not (AArguments.Items[0] is TJSONString) or
    not (AArguments.Items[1] is TJSONNumber) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TLspBoundaryText.NeedsUriAndLine].Fmt([cCommand]));
  end;
  mUri := AArguments.Items[0].Value;
  if not AReadText(mUri, mText) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[TLspBoundaryText.NotReadable].Fmt([mUri]));
  end;
  mTree := TSyntaxTreeCache.Parse(mText);
  try
    mRoutine := RoutineOf(mTree, Max(0, TJSONNumber(AArguments.Items[1]).AsInt), '');
    if mRoutine = nil then
    begin
      Exit(TJSONNull.Create);
    end;
    Result := ToJson(mUri, mRoutine.StartPos.Line, TBoundaryCases.Find(mTree, mRoutine, MaxOf(AArguments)));
  finally
    mTree.Free;
  end;
end;

class procedure TLspBoundaryCases.Attach(ACommands: TLspCommands; const AReadText: TLspTestCasesReadText);
var
  mReadText: TLspTestCasesReadText;
begin
  mReadText := AReadText;
  ACommands.RegisterConcurrent(cCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := Execute(AArguments, mReadText);
    end);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.BoundaryCases', cTexts);

end.
