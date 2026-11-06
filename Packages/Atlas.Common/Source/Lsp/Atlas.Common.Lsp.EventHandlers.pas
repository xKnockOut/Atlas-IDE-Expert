unit Atlas.Common.Lsp.EventHandlers;

// Befehl atlas.server.eventHandlers (#856): alle Ereignis-Handler eines
// Projekts für „Beim nächsten Ereignis anhalten“ im IDE-Plugin.
// Argumente: [uri]
//   - uri: Projekt (.dproj, .dpr, .dpk), Ordner oder null (einziger
//     Arbeitsbereich); welche Dateien dazugehören, bestimmt das Projektmodell
//     wie bei atlas.server.debugDisplayRules.
// Antwort: {"format": 1,
//   "handlers": [{"form": "TfrmKunde", "component": "btnSpeichern",
//                 "componentClass": "TButton", "event": "OnClick",
//                 "handler": "btnSpeichernClick", "container": "TfrmKunde",
//                 "origin": "form"|"code", "file": "…\Kunde.pas", "line": 41,
//                 "bodyLine": 42,
//                 "source": "…\Kunde.dfm", "sourceLine": 12, "interval": 50}],
//   "unresolved": 2}
// line ist die Zeile (ab 0) des begin im Rumpf, bodyLine die der ersten
// Anweisung (bei leerem Rumpf des end): Dort hält das Plugin, weil dann die
// Parameter (Sender) schon auswertbar sind. Liegt der Rumpf nicht in der
// Unit des Formulars (geerbtes Formular), sucht der Index ihn in den
// Vorfahren der Klasse; ohne Treffer zählt der Handler zu unresolved und
// fehlt in handlers. interval nur, wenn die Formulardatei eines setzt.

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Index.Contract,
  Atlas.Common.Metrics.Collector,
  Atlas.Common.Dfm.EventHandlers,
  Atlas.Common.Lsp.Metrics;

type
  TLspEventHandlers = class
  public const
    cCommand = 'atlas.server.eventHandlers';
    cMaxDepth = 32;
  private
    FSourceFor: TLspMetricsSourceFunc;
    FReadText: TMetricsReadText;
    FIndex: ISymbolIndex;
    /// <summary>Rümpfe je Datei (klein) für die Suche in Vorfahren.</summary>
    FBodies: TObjectDictionary<string, TDictionary<string, TEventHandlerBody>>;
    function BodiesOf(const AFileName: string): TDictionary<string, TEventHandlerBody>;
    function ResolveInAncestors(var AHandler: TEventHandler): Boolean;
    /// <summary>Die .pas-Dateien aus AFiles, ohne Angabe die Projekt-Units des Index.</summary>
    function SourceFiles(const AFiles: TArray<string>): TArray<string>;
    /// <summary>Lesbare Formulardateien zur Unit AFileName mit dem Text AText.</summary>
    function FormsOf(const AFileName, AText: string): TArray<TEventHandlerForm>;
  public
    constructor Create(const ASourceFor: TLspMetricsSourceFunc; const AReadText: TMetricsReadText);
    destructor Destroy; override;
    /// <summary>Führt den Befehl aus; der Aufrufer übernimmt das Ergebnis.</summary>
    function Execute(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Handler der Units AFiles (leer = alle Projekt-Units des Index); AUnresolved zählt die ohne Rumpf.
    /// </summary>
    function Collect(const AFiles: TArray<string>; out AUnresolved: Integer): TArray<TEventHandler>;
    class function ToJson(const AHandlers: TArray<TEventHandler>; AUnresolved: Integer): string; static;
    /// <summary>Symbolindex für Projekt-Units und Vorfahren; ohne Index nur die übergebenen Dateien.</summary>
    property Index: ISymbolIndex read FIndex write FIndex;
  end;

implementation

uses
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Dfm.FormFiles,
  Atlas.Common.Documents.Uris;

const
  cOriginNames: array[TEventHandlerOrigin] of string = ('form', 'code');
  cClassKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType];

{ TLspEventHandlers }

constructor TLspEventHandlers.Create(const ASourceFor: TLspMetricsSourceFunc; const AReadText: TMetricsReadText);
begin
  inherited Create;
  FSourceFor := ASourceFor;
  FReadText := AReadText;
  FBodies := TObjectDictionary<string, TDictionary<string, TEventHandlerBody>>.Create([doOwnsValues]);
end;

destructor TLspEventHandlers.Destroy;
begin
  FBodies.Free;
  inherited;
end;

function TLspEventHandlers.BodiesOf(const AFileName: string): TDictionary<string, TEventHandlerBody>;
var
  mText: string;
  mTree: TSyntaxTree;
begin
  if FBodies.TryGetValue(LowerCase(AFileName), Result) then
  begin
    Exit;
  end;
  Result := TDictionary<string, TEventHandlerBody>.Create;
  FBodies.Add(LowerCase(AFileName), Result);
  if not (Assigned(FReadText) and FReadText(AFileName, mText)) then
  begin
    Exit;
  end;
  mTree := TSyntaxTreeCache.Parse(mText, nil);
  try
    TEventHandlers.Bodies(mTree, Result);
  finally
    mTree.Free;
  end;
end;

function TLspEventHandlers.ResolveInAncestors(var AHandler: TEventHandler): Boolean;
var
  mClassName, mFileName, mContainer: string;
  mDepth: Integer;
  mLocation: TSymbolLocation;
  mNext: string;
begin
  Result := False;
  if FIndex = nil then
  begin
    Exit;
  end;
  // Die Klasse selbst (Rumpf in einer anderen Unit, etwa per Include) und ihre Vorfahren.
  mClassName := AHandler.Container;
  mDepth := 0;
  while (mClassName <> '') and (mDepth < cMaxDepth) do
  begin
    mNext := '';
    for mLocation in FIndex.FindSymbols(mClassName) do
    begin
      if not (mLocation.Symbol.Kind in cClassKinds) then
      begin
        Continue;
      end;
      mFileName := mLocation.FileName;
      mContainer := AHandler.Container;
      AHandler.Container := mClassName;
      if TEventHandlers.Resolve(AHandler, mFileName, BodiesOf(mFileName)) then
      begin
        Exit(True);
      end;
      AHandler.Container := mContainer;
      if (mNext = '') and (Length(mLocation.Symbol.Ancestors) > 0) then
      begin
        mNext := mLocation.Symbol.Ancestors[0];
      end;
    end;
    mClassName := mNext;
    Inc(mDepth);
  end;
end;

function TLspEventHandlers.SourceFiles(const AFiles: TArray<string>): TArray<string>;
var
  mFileName: string;
  mUnit: TUnitIndex;
begin
  Result := nil;
  if Length(AFiles) > 0 then
  begin
    for mFileName in AFiles do
    begin
      if SameText(ExtractFileExt(mFileName), '.pas') then
      begin
        Result := Result + [mFileName];
      end;
    end;
    Exit;
  end;
  if FIndex = nil then
  begin
    Exit;
  end;
  for mUnit in FIndex.Units do
  begin
    if not mUnit.Library_ then
    begin
      Result := Result + [mUnit.FileName];
    end;
  end;
end;

function TLspEventHandlers.FormsOf(const AFileName, AText: string): TArray<TEventHandlerForm>;
var
  mFormFile: string;
  mForm: TEventHandlerForm;
begin
  Result := nil;
  for mFormFile in TFormFiles.FormFiles(AFileName, AText) do
  begin
    mForm := Default(TEventHandlerForm);
    mForm.FileName := mFormFile;
    if FReadText(mFormFile, mForm.Text) then
    begin
      Result := Result + [mForm];
    end;
  end;
end;

function TLspEventHandlers.Collect(const AFiles: TArray<string>; out AUnresolved: Integer): TArray<TEventHandler>;
var
  mFileName, mText: string;
  mFound, mHandler: TEventHandler;
begin
  Result := nil;
  AUnresolved := 0;
  FBodies.Clear;
  if not Assigned(FReadText) then
  begin
    Exit;
  end;
  for mFileName in SourceFiles(AFiles) do
  begin
    if not FReadText(mFileName, mText) then
    begin
      Continue;
    end;
    for mFound in TEventHandlers.Collect(mFileName, mText, FormsOf(mFileName, mText)) do
    begin
      mHandler := mFound;
      if (mHandler.Line < 0) and not ResolveInAncestors(mHandler) then
      begin
        Inc(AUnresolved);
        Continue;
      end;
      Result := Result + [mHandler];
    end;
  end;
  FBodies.Clear;
end;

class function TLspEventHandlers.ToJson(const AHandlers: TArray<TEventHandler>; AUnresolved: Integer): string;
var
  mRoot, mItem: TJSONObject;
  mList: TJSONArray;
  mHandler: TEventHandler;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('format', TJSONNumber.Create(1));
    mList := TJSONArray.Create;
    mRoot.AddPair('handlers', mList);
    for mHandler in AHandlers do
    begin
      mItem := TJSONObject.Create;
      mList.AddElement(mItem);
      mItem.AddPair('form', mHandler.FormClass);
      mItem.AddPair('component', mHandler.Component);
      mItem.AddPair('componentClass', mHandler.ComponentClass);
      mItem.AddPair('event', mHandler.Event);
      mItem.AddPair('handler', mHandler.Handler);
      mItem.AddPair('container', mHandler.Container);
      mItem.AddPair('origin', cOriginNames[mHandler.Origin]);
      mItem.AddPair('file', mHandler.FileName);
      mItem.AddPair('line', TJSONNumber.Create(mHandler.Line));
      mItem.AddPair('bodyLine', TJSONNumber.Create(mHandler.BodyLine));
      mItem.AddPair('source', mHandler.SourceFile);
      mItem.AddPair('sourceLine', TJSONNumber.Create(mHandler.SourceLine));
      if mHandler.Interval >= 0 then
      begin
        mItem.AddPair('interval', TJSONNumber.Create(mHandler.Interval));
      end;
    end;
    mRoot.AddPair('unresolved', TJSONNumber.Create(AUnresolved));
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

function TLspEventHandlers.Execute(const AArguments: TJSONArray): TJSONValue;
var
  mFileName: string;
  mSource: TLspMetricsSource;
  mHandlers: TArray<TEventHandler>;
  mUnresolved: Integer;
begin
  mFileName := '';
  if (AArguments <> nil) and (AArguments.Count > 0) and (AArguments.Items[0] is TJSONString) then
  begin
    mFileName := TDocumentUris.ToPath(AArguments.Items[0].Value);
  end;
  if not (Assigned(FSourceFor) and FSourceFor(mFileName, True, mSource)) then
  begin
    mSource := Default(TLspMetricsSource);
  end;
  mHandlers := Collect(mSource.Files, mUnresolved);
  Result := TJSONObject.ParseJSONValue(ToJson(mHandlers, mUnresolved));
end;

end.
