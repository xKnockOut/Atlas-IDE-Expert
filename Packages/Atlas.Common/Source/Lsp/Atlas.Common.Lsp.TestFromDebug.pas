unit Atlas.Common.Lsp.TestFromDebug;

// Befehl atlas.server.testFromDebugStop [uri, zeile, anfrage] (#1873): Test
// aus dem Debug-Halt. Das Plugin fragt zweimal:
//   - mode "describe": Was gibt es an der Zeile (Methode, Parameter, Felder
//     der Klasse, Ergebnistyp, Testunit)? Mit Werten aus dem Debugger kommen
//     dazu je Wert das Literal (bzw. todo) und ein vorgeschlagener Testname.
//   - mode "create": WorkspaceEdit, das den Test in die Testunit einträgt bzw.
//     sie damit anlegt (wie „Testfall anlegen“, #1226), Datei und Name.
// Anfrage: parameters/fields als Objekte {name, text}, kind ("works" oder
// "raises"), expected, exceptionClass, testName, maxArray, stoppedAt.
// Kern: Atlas.Common.Editing.TestFromDebug; Ort und Edit: TLspTestUnits.

interface

uses
  System.JSON,
  Atlas.Common.Lsp.TestUnits,
  Atlas.Common.Editing.TestFromDebug;

type
  TLspTestFromDebug = class
  public const
    cCommand = 'atlas.server.testFromDebugStop';
    cModeDescribe = 'describe';
    cModeCreate = 'create';
    cKindRaises = 'raises';
  private
    FTestUnits: TLspTestUnits;
  public
    /// <summary>ATestUnits gehört dem Aufrufer.</summary>
    constructor Create(ATestUnits: TLspTestUnits);
    /// <summary>Anfrage aus dem JSON-Objekt des Plugins; nil ergibt die leere Anfrage.</summary>
    class function ReadRequest(AObject: TJSONObject): TDebugStopRequest; static;
    /// <summary>atlas.server.testFromDebugStop [uri, zeile, anfrage]; Antwort siehe Kopf. Fehler stehen in
    /// "reason".</summary>
    function Execute(const AArguments: TJSONArray): TJSONValue;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.Json,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Editing.TestDrafts,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TLspTestFromDebugText = (NeedsArguments, NoTestableRoutine, NotAdded);

const
  cTexts: array[TLspTestFromDebugText] of TAtlasText = (
    (De: ' braucht URI, Zeile und Anfrage'; En: ' needs URI, line and request'),
    (De: 'An dieser Stelle steht keine Methode, für die sich ein Test anlegen lässt (Testunit fehlt oder lässt ' +
      'sich nicht anlegen)';
     En: 'There is no method here that a test can be created for (the test unit is missing or cannot be ' +
       'created)'),
    (De: 'Der Test ließ sich nicht in die Testunit %s eintragen'; En: 'The test could not be added to test unit %s'));

{$SCOPEDENUMS OFF}

constructor TLspTestFromDebug.Create(ATestUnits: TLspTestUnits);
begin
  inherited Create;
  FTestUnits := ATestUnits;
end;

/// <summary>Werte [{name, text}] aus AObject.AName.</summary>
function ValuesOf(AObject: TJSONObject; const AName: string): TDebugStopValues;
var
  mArray: TJSONArray;
  mItem: TJSONValue;
begin
  Result := nil;
  mArray := TJsonRead.Items(AObject, AName);
  if mArray = nil then
  begin
    Exit;
  end;
  for mItem in mArray do
  begin
    if mItem is TJSONObject then
    begin
      Result := Result + [TDebugStopValue.Create(TJsonRead.Text(TJSONObject(mItem), 'name'),
        TJsonRead.Text(TJSONObject(mItem), 'text'))];
    end;
  end;
end;

class function TLspTestFromDebug.ReadRequest(AObject: TJSONObject): TDebugStopRequest;
begin
  Result := TDebugStopRequest.Empty;
  if AObject = nil then
  begin
    Exit;
  end;
  Result.Parameters := ValuesOf(AObject, 'parameters');
  Result.Fields := ValuesOf(AObject, 'fields');
  if SameText(TJsonRead.Text(AObject, 'kind'), cKindRaises) then
  begin
    Result.Kind := TTestDraftKind.Raises;
  end;
  Result.Expected := TJsonRead.Text(AObject, 'expected');
  Result.ExceptionClass := TJsonRead.Text(AObject, 'exceptionClass');
  Result.TestName := TJsonRead.Text(AObject, 'testName');
  Result.MaxArray := TJsonRead.IntOr(AObject, 'maxArray', TTestFromDebug.cDefaultMaxArray);
  Result.StoppedAt := TJsonRead.Text(AObject, 'stoppedAt');
end;

/// <summary>[{name, type, modifier, accessible, literal?, todo?}] zu AValues; Literale aus den Texten in
/// AFromDebugger.</summary>
function ValuesJson(const AValues: TArray<TTestDraftValue>; const AFromDebugger: TDebugStopValues;
  AMaxArray: Integer): TJSONArray;
var
  mValue: TTestDraftValue;
  mStop: TDebugStopValue;
  mItem: TJSONObject;
  mLiteral: string;
begin
  Result := TJSONArray.Create;
  for mValue in AValues do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('name', mValue.Name);
    mItem.AddPair('type', mValue.TypeName);
    mItem.AddPair('modifier', mValue.Modifier);
    mItem.AddPair('accessible', TJSONBool.Create(mValue.Accessible));
    for mStop in AFromDebugger do
    begin
      if SameText(mStop.Name, mValue.Name) then
      begin
        mItem.AddPair('todo', TJSONBool.Create(not TTestFromDebug.Literal(mStop.Text, mValue.TypeName, AMaxArray,
          mLiteral)));
        mItem.AddPair('literal', mLiteral);
      end;
    end;
    Result.AddElement(mItem);
  end;
end;

/// <summary>Antwort auf "describe".</summary>
procedure Describe(AAnswer: TJSONObject; const APlace: TTestDraftPlace; const ARequest: TDebugStopRequest);
var
  mFields: TArray<TTestDraftValue>;
begin
  mFields := nil;
  if not APlace.Draft.ClassMethod and (APlace.Draft.ClassName <> '') then
  begin
    mFields := TTestFromDebug.FieldsOf(APlace.Target.Source, APlace.Draft.ClassName);
  end;
  AAnswer.AddPair('target', APlace.Draft.Target);
  AAnswer.AddPair('className', APlace.Draft.ClassName);
  AAnswer.AddPair('method', APlace.Draft.MethodName);
  AAnswer.AddPair('classMethod', TJSONBool.Create(APlace.Draft.ClassMethod));
  AAnswer.AddPair('callable', TJSONBool.Create(not APlace.Draft.Bare));
  AAnswer.AddPair('resultType', APlace.Draft.ResultType);
  AAnswer.AddPair('parameters', ValuesJson(APlace.Draft.Parameters, ARequest.Parameters, ARequest.MaxArray));
  AAnswer.AddPair('fields', ValuesJson(mFields, ARequest.Fields, ARequest.MaxArray));
  AAnswer.AddPair('testUnit', APlace.Target.Counterpart);
  AAnswer.AddPair('testUnitExists', TJSONBool.Create(APlace.Target.CounterpartFile <> ''));
  AAnswer.AddPair('testName', TTestFromDebug.SuggestName(APlace.Draft.MethodName, ARequest.Parameters,
    ARequest.Kind, ARequest.ExceptionClass));
end;

/// <summary>Antwort auf "create"; "reason", wenn sich nichts eintragen ließ.</summary>
procedure CreateTest(AAnswer: TJSONObject; ATestUnits: TLspTestUnits; const APlace: TTestDraftPlace;
  const ARequest: TDebugStopRequest);
var
  mPlace: TTestDraftPlace;
  mFields: TArray<TTestDraftValue>;
  mEdit: TJSONObject;
  mFile, mName: string;
begin
  mPlace := APlace;
  mFields := nil;
  if mPlace.Draft.ClassName <> '' then
  begin
    mFields := TTestFromDebug.FieldsOf(mPlace.Target.Source, mPlace.Draft.ClassName);
  end;
  TTestFromDebug.Apply(ARequest, mFields, mPlace.Draft);
  mEdit := ATestUnits.DraftEdit(mPlace, mFile, mName);
  if mEdit = nil then
  begin
    AAnswer.AddPair('reason', cTexts[TLspTestFromDebugText.NotAdded].Fmt([mPlace.Target.Counterpart]));
    Exit;
  end;
  AAnswer.AddPair('edit', mEdit);
  AAnswer.AddPair('uri', TDocumentUris.FromPath(mFile));
  AAnswer.AddPair('testName', mName);
  AAnswer.AddPair('fixture', mPlace.Draft.Fixture);
end;

function TLspTestFromDebug.Execute(const AArguments: TJSONArray): TJSONValue;
var
  mAnswer, mRequestJson: TJSONObject;
  mPlace: TTestDraftPlace;
  mRequest: TDebugStopRequest;
begin
  if (AArguments = nil) or (AArguments.Count < 2) then
  begin
    raise EArgumentException.Create(cCommand + cTexts[TLspTestFromDebugText.NeedsArguments].Text);
  end;
  mRequestJson := nil;
  if (AArguments.Count > 2) and (AArguments.Items[2] is TJSONObject) then
  begin
    mRequestJson := TJSONObject(AArguments.Items[2]);
  end;
  mRequest := ReadRequest(mRequestJson);
  mAnswer := TJSONObject.Create;
  Result := mAnswer;
  if not FTestUnits.DraftPlace(AArguments.Items[0].Value, StrToIntDef(AArguments.Items[1].Value, -1), mPlace) then
  begin
    mAnswer.AddPair('reason', cTexts[TLspTestFromDebugText.NoTestableRoutine].Text);
    Exit;
  end;
  if (mRequestJson <> nil) and SameText(TJsonRead.Text(mRequestJson, 'mode'), cModeCreate) then
  begin
    CreateTest(mAnswer, FTestUnits, mPlace, mRequest);
  end
  else
  begin
    Describe(mAnswer, mPlace, mRequest);
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.TestFromDebug', cTexts);

end.
