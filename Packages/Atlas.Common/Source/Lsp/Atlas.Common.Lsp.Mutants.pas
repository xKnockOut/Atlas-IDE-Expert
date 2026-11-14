unit Atlas.Common.Lsp.Mutants;

// Mutanten einer Unit für das Plugin (#1460, Mutationslauf in der IDE). Logik in Atlas.Common.Mutation.Generator,
// Ausgabe wie get_mutants und --mutate --format json (Atlas.Common.Mutation.Report); den Text (offenes Dokument
// vor der Platte) liefert die Shell.
//
// Befehl atlas.server.mutants [uri, optionen?]; optionen ist ein Objekt mit
//   routine     "TFoo.Bar" oder "Bar"; fehlt bzw. '' = alle Routinen
//   operators   Kennungen wie "boundary"; fehlt bzw. leer = alle; unbekannte Kennungen sind ein Fehler
//   defines     Symbole der aktiven Zweige (DCC_Define des Projekts); fehlt = Vordefinitionen
//   firstLine, lastLine   nur Stellen, die in diesen Zeilen (0-basiert) beginnen; fehlt = keine Grenze
// Antwort: das JSON von TMutationReport.Json (format 1, file, count, operators, mutants) und dazu uri und
// routines: je Routine mit Mutanten name, line und endLine (0-basiert, Kopf bis end). Über diese Zeilen bildet
// das Plugin die Prüfsumme, mit der es ein gemerktes Ergebnis als veraltet erkennt.

interface

uses
  System.JSON,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Lsp.Commands,
  Atlas.Common.Lsp.TestCases,
  Atlas.Common.Mutation.Contract;

type
  TLspMutants = class
  public const
    cCommand = 'atlas.server.mutants';
  public
    /// <summary>Meldet den Befehl an (nebenläufig: liest nur).</summary>
    class procedure Attach(ACommands: TLspCommands; const AReadText: TLspTestCasesReadText); static;
    /// <summary>Optionen aus dem zweiten Argument; False mit Grund in AError bei unbekannten Operatoren.</summary>
    class function OptionsOf(AValue: TJSONValue; out AOptions: TMutationOptions; out AError: string): Boolean;
      static;
    /// <summary>Zeilen (Kopf bis end, 0-basiert) der Routinen ANames in ATree, Namen wie TMutant.Routine.
    /// </summary>
    class function RoutineRanges(ATree: TSyntaxTree; const ANames: TArray<string>): TJSONArray; static;
    /// <summary>Befehl mit dem Text des Dokuments AArguments[0].</summary>
    class function Execute(const AArguments: TJSONArray; const AReadText: TLspTestCasesReadText): TJSONValue; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Mutation.Generator,
  Atlas.Common.Mutation.Report,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  TLspMutantsText = (NeedsUri, NotReadable, UnknownOperators);

const
  cTexts: array[TLspMutantsText] of TAtlasText = (
    (De: '%s braucht eine URI'; En: '%s needs a URI'),
    (De: '%s ist nicht lesbar'; En: '%s cannot be read'),
    (De: 'Unbekannte Operatoren: %s'; En: 'Unknown operators: %s'));

{$SCOPEDENUMS OFF}

function StringsOf(AObject: TJSONObject; const AName: string): TArray<string>;
var
  mValue: TJSONValue;
  mIndex: Integer;
begin
  Result := nil;
  mValue := AObject.GetValue(AName);
  if not (mValue is TJSONArray) then
  begin
    Exit;
  end;
  for mIndex := 0 to TJSONArray(mValue).Count - 1 do
  begin
    if TJSONArray(mValue).Items[mIndex] is TJSONString then
    begin
      Result := Result + [TJSONArray(mValue).Items[mIndex].Value];
    end;
  end;
end;

function LineOf(AObject: TJSONObject; const AName: string): Integer;
var
  mValue: TJSONValue;
begin
  Result := -1;
  mValue := AObject.GetValue(AName);
  if mValue is TJSONNumber then
  begin
    Result := TJSONNumber(mValue).AsInt;
  end;
end;

class function TLspMutants.OptionsOf(AValue: TJSONValue; out AOptions: TMutationOptions; out AError: string): Boolean;
var
  mObject: TJSONObject;
  mIds, mUnknown: TArray<string>;
begin
  AOptions := TMutationOptions.Default;
  AError := '';
  Result := True;
  if not (AValue is TJSONObject) then
  begin
    Exit;
  end;
  mObject := TJSONObject(AValue);
  if mObject.GetValue('routine') is TJSONString then
  begin
    AOptions.Routine := Trim(mObject.GetValue('routine').Value);
  end;
  mIds := StringsOf(mObject, 'operators');
  if mIds <> nil then
  begin
    AOptions.Operators := TMutation.ParseOperators(mIds, mUnknown);
    if mUnknown <> nil then
    begin
      AError := cTexts[TLspMutantsText.UnknownOperators].Fmt([string.Join(', ', mUnknown)]);
      Exit(False);
    end;
  end;
  AOptions.Defines := StringsOf(mObject, 'defines');
  AOptions.FirstLine := LineOf(mObject, 'firstLine');
  AOptions.LastLine := LineOf(mObject, 'lastLine');
end;

/// <summary>Zeilen der Routine ANode als JSON-Objekt.</summary>
function RangeJson(ANode: TSyntaxNode; const AName: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', AName);
  Result.AddPair('line', TJSONNumber.Create(ANode.StartPos.Line));
  Result.AddPair('endLine', TJSONNumber.Create(ANode.EndPos.Line));
end;

/// <summary>Routine ANode (Name AName) und ihre lokalen Routinen in AResult, soweit in ANames.</summary>
procedure AddRanges(ANode: TSyntaxNode; const AName: string; ANames: TDictionary<string, Boolean>;
  AResult: TJSONArray);
var
  mIndex: Integer;
begin
  if ANames.ContainsKey(AName) then
  begin
    AResult.AddElement(RangeJson(ANode, AName));
  end;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    if ANode[mIndex].Kind = TSyntaxKind.RoutineDecl then
    begin
      AddRanges(ANode[mIndex], AName + '.' + ANode[mIndex].Name, ANames, AResult);
    end;
  end;
end;

class function TLspMutants.RoutineRanges(ATree: TSyntaxTree; const ANames: TArray<string>): TJSONArray;
var
  mNames: TDictionary<string, Boolean>;
  mStack: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mName: string;
  mIndex: Integer;
begin
  // Namensbildung wie im Generator: Routine auf oberster Ebene mit ihrem Namen, lokale mit dem der äußeren davor.
  Result := TJSONArray.Create;
  mNames := TDictionary<string, Boolean>.Create;
  mStack := TStack<TSyntaxNode>.Create;
  try
    for mName in ANames do
    begin
      mNames.AddOrSetValue(mName, True);
    end;
    mStack.Push(ATree.Root);
    while mStack.Count > 0 do
    begin
      mNode := mStack.Pop;
      if mNode.Kind = TSyntaxKind.RoutineDecl then
      begin
        AddRanges(mNode, mNode.Name, mNames, Result);
        Continue;
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mStack.Push(mNode[mIndex]);
      end;
    end;
  finally
    mStack.Free;
    mNames.Free;
  end;
end;

/// <summary>Namen der Routinen von AMutants, jeder einmal, in der Reihenfolge des Auftretens.</summary>
function RoutineNames(const AMutants: TArray<TMutant>): TArray<string>;
var
  mMutant: TMutant;
  mLast: string;
begin
  Result := nil;
  mLast := '';
  for mMutant in AMutants do
  begin
    // Mutanten sind nach Stelle sortiert: eine Routine kann nach einer lokalen wiederkommen.
    if (mMutant.Routine <> mLast) and (IndexStr(mMutant.Routine, Result) < 0) then
    begin
      Result := Result + [mMutant.Routine];
    end;
    mLast := mMutant.Routine;
  end;
end;

class function TLspMutants.Execute(const AArguments: TJSONArray; const AReadText: TLspTestCasesReadText): TJSONValue;
var
  mUri, mText, mError: string;
  mOptions: TMutationOptions;
  mOptionsValue: TJSONValue;
  mResult: TJSONValue;
  mTree: TSyntaxTree;
  mProcessed: TPreprocessorResult;
  mMutants: TArray<TMutant>;
begin
  if (AArguments = nil) or (AArguments.Count < 1) or not (AArguments.Items[0] is TJSONString) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[TLspMutantsText.NeedsUri].Fmt([cCommand]));
  end;
  mUri := AArguments.Items[0].Value;
  mOptionsValue := nil;
  if AArguments.Count > 1 then
  begin
    mOptionsValue := AArguments.Items[1];
  end;
  if not OptionsOf(mOptionsValue, mOptions, mError) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, mError);
  end;
  if not AReadText(mUri, mText) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[TLspMutantsText.NotReadable].Fmt([mUri]));
  end;
  // Baum wie TMutationGenerator.ForText; er liefert hier auch die Zeilen der Routinen.
  mTree := TSyntaxTreeCache.ParseActive(mText, TPascalPreprocessor.EditorOptions(mOptions.Defines), nil,
    mProcessed);
  try
    mMutants := TMutationGenerator.ForTree(mTree, mText, mOptions);
    mResult := TJSONObject.ParseJSONValue(TMutationReport.Json(mUri, mMutants));
    if not (mResult is TJSONObject) then
    begin
      mResult.Free;
      Exit(TJSONNull.Create);
    end;
    TJSONObject(mResult).AddPair('uri', mUri);
    TJSONObject(mResult).AddPair('routines', RoutineRanges(mTree, RoutineNames(mMutants)));
  finally
    mTree.Free;
  end;
  Result := mResult;
end;

class procedure TLspMutants.Attach(ACommands: TLspCommands; const AReadText: TLspTestCasesReadText);
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
  TAtlasTextTables.Add('Atlas.Common.Lsp.Mutants', cTexts);

end.
