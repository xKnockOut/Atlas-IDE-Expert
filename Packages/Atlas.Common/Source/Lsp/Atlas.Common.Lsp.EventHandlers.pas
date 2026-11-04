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
    Command = 'atlas.server.eventHandlers';
    MaxDepth = 32;
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
  OriginNames: array[TEventHandlerOrigin] of string = ('form', 'code');
  ClassKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType];

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
  Text: string;
  Tree: TSyntaxTree;
begin
  if FBodies.TryGetValue(LowerCase(AFileName), Result) then
  begin
    Exit;
  end;
  Result := TDictionary<string, TEventHandlerBody>.Create;
  FBodies.Add(LowerCase(AFileName), Result);
  if not (Assigned(FReadText) and FReadText(AFileName, Text)) then
  begin
    Exit;
  end;
  Tree := TSyntaxTreeCache.Parse(Text, nil);
  try
    TEventHandlers.Bodies(Tree, Result);
  finally
    Tree.Free;
  end;
end;

function TLspEventHandlers.ResolveInAncestors(var AHandler: TEventHandler): Boolean;
var
  ClassName, FileName, Container: string;
  Depth: Integer;
  Location: TSymbolLocation;
  Next: string;
begin
  Result := False;
  if FIndex = nil then
  begin
    Exit;
  end;
  // Die Klasse selbst (Rumpf in einer anderen Unit, etwa per Include) und ihre Vorfahren.
  ClassName := AHandler.Container;
  Depth := 0;
  while (ClassName <> '') and (Depth < MaxDepth) do
  begin
    Next := '';
    for Location in FIndex.FindSymbols(ClassName) do
    begin
      if not (Location.Symbol.Kind in ClassKinds) then
      begin
        Continue;
      end;
      FileName := Location.FileName;
      Container := AHandler.Container;
      AHandler.Container := ClassName;
      if TEventHandlers.Resolve(AHandler, FileName, BodiesOf(FileName)) then
      begin
        Exit(True);
      end;
      AHandler.Container := Container;
      if (Next = '') and (Length(Location.Symbol.Ancestors) > 0) then
      begin
        Next := Location.Symbol.Ancestors[0];
      end;
    end;
    ClassName := Next;
    Inc(Depth);
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
  Root, Item: TJSONObject;
  List: TJSONArray;
  Handler: TEventHandler;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('format', TJSONNumber.Create(1));
    List := TJSONArray.Create;
    Root.AddPair('handlers', List);
    for Handler in AHandlers do
    begin
      Item := TJSONObject.Create;
      List.AddElement(Item);
      Item.AddPair('form', Handler.FormClass);
      Item.AddPair('component', Handler.Component);
      Item.AddPair('componentClass', Handler.ComponentClass);
      Item.AddPair('event', Handler.Event);
      Item.AddPair('handler', Handler.Handler);
      Item.AddPair('container', Handler.Container);
      Item.AddPair('origin', OriginNames[Handler.Origin]);
      Item.AddPair('file', Handler.FileName);
      Item.AddPair('line', TJSONNumber.Create(Handler.Line));
      Item.AddPair('bodyLine', TJSONNumber.Create(Handler.BodyLine));
      Item.AddPair('source', Handler.SourceFile);
      Item.AddPair('sourceLine', TJSONNumber.Create(Handler.SourceLine));
      if Handler.Interval >= 0 then
      begin
        Item.AddPair('interval', TJSONNumber.Create(Handler.Interval));
      end;
    end;
    Root.AddPair('unresolved', TJSONNumber.Create(AUnresolved));
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function TLspEventHandlers.Execute(const AArguments: TJSONArray): TJSONValue;
var
  FileName: string;
  Source: TLspMetricsSource;
  Handlers: TArray<TEventHandler>;
  Unresolved: Integer;
begin
  FileName := '';
  if (AArguments <> nil) and (AArguments.Count > 0) and (AArguments.Items[0] is TJSONString) then
  begin
    FileName := TDocumentUris.ToPath(AArguments.Items[0].Value);
  end;
  if not (Assigned(FSourceFor) and FSourceFor(FileName, True, Source)) then
  begin
    Source := Default(TLspMetricsSource);
  end;
  Handlers := Collect(Source.Files, Unresolved);
  Result := TJSONObject.ParseJSONValue(ToJson(Handlers, Unresolved));
end;

end.
