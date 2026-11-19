unit Atlas.Common.Lsp.DataAccessSites;

// Befehl atlas.server.dataAccessSites (#870): eigene Aufrufstellen von
// Datenbank- und HTTP-Klassen für „Anhalten bei Datenzugriff“ im IDE-Plugin.
// Argumente: [uri, classes]
//   - uri: Projekt (.dproj, .dpr, .dpk), Ordner oder null (einziger
//     Arbeitsbereich); welche Dateien dazugehören, bestimmt das Projektmodell
//     wie bei atlas.server.eventHandlers.
//   - classes: beobachtete Klassen, [{"name": "TFDQuery", "kind": "sql",
//     "methods": ["Open", "ExecSQL", "Execute"]}, …]. Welche Klassen es gibt
//     und welche Methoden zählen, entscheidet das Plugin (Einstellung
//     debug.dataBreaks.classes); der Server kennt keine eigene Liste.
// Antwort: {"format": 1,
//   "sites": [{"file": "…\Kunde.pas", "line": 41, "character": 10,
//              "breakLine": 41, "class": "TFDQuery", "kind": "sql",
//              "method": "ExecSQL", "receiver": "qryKunde",
//              "receiverType": "TKundenQuery", "arguments": ["'…'"],
//              "routine": "TfrmKunde.Speichern"}],
//   "unresolved": 3}
// line/character: Stelle des Methodennamens (ab 0); breakLine: Zeile der
// Anweisung, an der der Haltepunkt steht. class ist der Eintrag aus classes,
// der zum Typ des Empfängers oder seinem nächsten Vorfahren passt, kind und
// methods kommen von dort. unresolved zählt Aufrufe mit passendem
// Methodennamen, deren Empfängertyp sich nicht bestimmen ließ. arguments
// enthält den Quelltext jedes Arguments in einer Zeile; zu lange Argumente
// stehen leer darin (das Plugin wertet sie dann nicht aus).

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Metrics.Collector,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.DataAccessCalls,
  Atlas.Common.Lsp.Metrics;

type
  /// <summary>Eine beobachtete Klasse samt ihrer Methoden.</summary>
  TDataAccessClass = record
    Name: string;
    /// <summary>sql oder http; der Server reicht den Wert nur durch.</summary>
    Kind: string;
    Methods: TArray<string>;
  end;

  TDataAccessSite = record
    FileName: string;
    /// <summary>Stelle des Methodennamens (ab 0).</summary>
    Position: TTextPosition;
    /// <summary>Zeile (ab 0) der Anweisung um den Aufruf.</summary>
    BreakLine: Integer;
    /// <summary>Passender Eintrag aus den beobachteten Klassen.</summary>
    WatchedClass: string;
    Kind: string;
    Method: string;
    Receiver: string;
    /// <summary>Deklarierter Typ des Empfängers (auch ein eigener Nachfahre).</summary>
    ReceiverType: string;
    Arguments: TArray<string>;
    Routine: string;
  end;

  /// <summary>Namensräume des Projekts für die Namensauflösung.</summary>
  TLspDataAccessNamespacesFunc = reference to function: TArray<string>;

  TLspDataAccessSites = class
  public const
    cCommand = 'atlas.server.dataAccessSites';
    cMaxDepth = 32;
    /// <summary>Längere Argumente gibt der Befehl leer zurück.</summary>
    cMaxArgument = 2000;
  private
    FSourceFor: TLspMetricsSourceFunc;
    FReadText: TMetricsReadText;
    FIndex: ISymbolIndex;
    FEnsureUnit: TEnsureUnitFunc;
    FNamespaces: TLspDataAccessNamespacesFunc;
    class function MethodsOf(const AClasses: TArray<TDataAccessClass>): TArray<string>; static;
    class function HasMethod(const AClass: TDataAccessClass; const AMethod: string): Boolean; static;
    class function SameTypeName(const ATypeName, AClassName: string): Boolean; static;
    class function OneLine(const AText: string; ANode: TSyntaxNode; AMax: Integer): string; static;
    /// <summary>Typ des Empfängers und seine Vorfahren, der eigene zuerst; False, wenn er nicht feststeht.
    /// </summary>
    function TypeChain(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
      AReceiver: TSyntaxNode; out AChain: TArray<string>): Boolean;
    function Match(const AChain: TArray<string>; const AClasses: TArray<TDataAccessClass>; const AMethod: string;
      out AClass: TDataAccessClass): Boolean;
    function SiteOf(const AFileName, AText: string; const ACall: TDataAccessCall; const AClass: TDataAccessClass;
      const AReceiverType: string): TDataAccessSite;
    procedure CollectFile(AResolver: TNameResolver; const AFileName, AText: string;
      const AClasses: TArray<TDataAccessClass>; var ASites: TArray<TDataAccessSite>; var AUnresolved: Integer);
  public
    constructor Create(const ASourceFor: TLspMetricsSourceFunc; const AReadText: TMetricsReadText;
      const AIndex: ISymbolIndex; const AEnsureUnit: TEnsureUnitFunc; const ANamespaces: TLspDataAccessNamespacesFunc);
    /// <summary>Führt den Befehl aus; der Aufrufer übernimmt das Ergebnis.</summary>
    function Execute(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Aufrufstellen in den Units AFiles (leer = alle Projekt-Units des Index).</summary>
    function Collect(const AFiles: TArray<string>; const AClasses: TArray<TDataAccessClass>;
      out AUnresolved: Integer): TArray<TDataAccessSite>;
    /// <summary>classes aus den Argumenten; Einträge ohne Namen oder Methoden fallen weg.</summary>
    class function ParseClasses(AValue: TJSONValue): TArray<TDataAccessClass>; static;
    class function ToJson(const ASites: TArray<TDataAccessSite>; AUnresolved: Integer): string; static;
  end;

implementation

uses
  System.Generics.Collections, // Inline-Funktionen von TJSONArray (H2443)
  System.StrUtils,
  Atlas.Text.Json,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.EventHandlers;

{ TLspDataAccessSites }

constructor TLspDataAccessSites.Create(const ASourceFor: TLspMetricsSourceFunc; const AReadText: TMetricsReadText;
  const AIndex: ISymbolIndex; const AEnsureUnit: TEnsureUnitFunc; const ANamespaces: TLspDataAccessNamespacesFunc);
begin
  inherited Create;
  FSourceFor := ASourceFor;
  FReadText := AReadText;
  FIndex := AIndex;
  FEnsureUnit := AEnsureUnit;
  FNamespaces := ANamespaces;
end;

class function TLspDataAccessSites.MethodsOf(const AClasses: TArray<TDataAccessClass>): TArray<string>;
var
  mClass: TDataAccessClass;
  mMethod: string;
begin
  Result := nil;
  for mClass in AClasses do
  begin
    for mMethod in mClass.Methods do
    begin
      if IndexText(mMethod, Result) < 0 then
      begin
        Result := Result + [mMethod];
      end;
    end;
  end;
end;

class function TLspDataAccessSites.HasMethod(const AClass: TDataAccessClass; const AMethod: string): Boolean;
begin
  Result := IndexText(AMethod, AClass.Methods) >= 0;
end;

class function TLspDataAccessSites.SameTypeName(const ATypeName, AClassName: string): Boolean;
var
  mName: string;
  mDot: Integer;
begin
  // Unit-Präfix (FireDAC.Comp.Client.TFDQuery) zählt nicht.
  mName := ATypeName;
  mDot := LastDelimiter('.', mName);
  if mDot > 0 then
  begin
    mName := Copy(mName, mDot + 1, MaxInt);
  end;
  Result := SameText(mName, AClassName);
end;

class function TLspDataAccessSites.OneLine(const AText: string; ANode: TSyntaxNode; AMax: Integer): string;
begin
  Result := '';
  if (ANode = nil) or (ANode.EndOffset <= ANode.StartOffset) or (ANode.EndOffset > Length(AText)) or
    (ANode.EndOffset - ANode.StartOffset > AMax) then
  begin
    Exit;
  end;
  Result := Copy(AText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  Result := Result.Replace(#13#10, ' ').Replace(#10, ' ').Replace(#13, ' ').Trim;
end;

function TLspDataAccessSites.TypeChain(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  AReceiver: TSyntaxNode; out AChain: TArray<string>): Boolean;
var
  mSymbol, mType, mAncestor: TResolvedSymbol;
  mFound: Boolean;
  mDepth: Integer;
begin
  AChain := nil;
  if not AResolver.NodeType(ATree, AFileName, AReceiver, mSymbol, mType, mFound) then
  begin
    Exit(False);
  end;
  if not mFound then
  begin
    // Typ ohne Deklaration im Index (Bibliothek fehlt): nur sein Name.
    if mSymbol.TypeName <> '' then
    begin
      AChain := [mSymbol.TypeName];
    end;
    Exit(Length(AChain) > 0);
  end;
  AChain := [mType.Name];
  mDepth := 0;
  while (mDepth < cMaxDepth) and AResolver.AncestorOf(mType, mAncestor) do
  begin
    AChain := AChain + [mAncestor.Name];
    mType := mAncestor;
    Inc(mDepth);
  end;
  Result := True;
end;

function TLspDataAccessSites.Match(const AChain: TArray<string>; const AClasses: TArray<TDataAccessClass>;
  const AMethod: string; out AClass: TDataAccessClass): Boolean;
var
  mTypeName: string;
  mClass: TDataAccessClass;
begin
  // Der nächste Vorfahr gewinnt: TKundenQuery = class(TFDQuery) zählt als TFDQuery, auch wenn TDataSet folgt.
  for mTypeName in AChain do
  begin
    for mClass in AClasses do
    begin
      if SameTypeName(mTypeName, mClass.Name) then
      begin
        AClass := mClass;
        Exit(HasMethod(mClass, AMethod));
      end;
    end;
  end;
  AClass := Default(TDataAccessClass);
  Result := False;
end;

function TLspDataAccessSites.SiteOf(const AFileName, AText: string; const ACall: TDataAccessCall;
  const AClass: TDataAccessClass; const AReceiverType: string): TDataAccessSite;
var
  mArgument: TSyntaxNode;
begin
  Result := Default(TDataAccessSite);
  Result.FileName := AFileName;
  Result.Position := ACall.Position;
  Result.BreakLine := ACall.BreakLine;
  Result.WatchedClass := AClass.Name;
  Result.Kind := AClass.Kind;
  Result.Method := ACall.Method;
  Result.Receiver := OneLine(AText, ACall.Receiver, cMaxArgument);
  Result.ReceiverType := AReceiverType;
  for mArgument in ACall.Arguments do
  begin
    Result.Arguments := Result.Arguments + [OneLine(AText, mArgument, cMaxArgument)];
  end;
  Result.Routine := ACall.Routine;
end;

procedure TLspDataAccessSites.CollectFile(AResolver: TNameResolver; const AFileName, AText: string;
  const AClasses: TArray<TDataAccessClass>; var ASites: TArray<TDataAccessSite>; var AUnresolved: Integer);
var
  mTree: TSyntaxTree;
  mCall: TDataAccessCall;
  mChain: TArray<string>;
  mClass: TDataAccessClass;
begin
  mTree := TSyntaxTreeCache.Parse(AText, nil);
  try
    AResolver.PinTree(mTree, AFileName);
    try
      for mCall in TDataAccessCalls.Collect(mTree, MethodsOf(AClasses)) do
      begin
        if not TypeChain(AResolver, mTree, AFileName, mCall.Receiver, mChain) then
        begin
          Inc(AUnresolved);
        end
        else if Match(mChain, AClasses, mCall.Method, mClass) then
        begin
          ASites := ASites + [SiteOf(AFileName, AText, mCall, mClass, mChain[0])];
        end;
      end;
    finally
      AResolver.UnpinTree;
    end;
  finally
    mTree.Free;
  end;
end;

function TLspDataAccessSites.Collect(const AFiles: TArray<string>; const AClasses: TArray<TDataAccessClass>;
  out AUnresolved: Integer): TArray<TDataAccessSite>;
var
  mResolver: TNameResolver;
  mFileName, mText: string;
begin
  Result := nil;
  AUnresolved := 0;
  if not Assigned(FReadText) or (Length(AClasses) = 0) then
  begin
    Exit;
  end;
  mResolver := TNameResolver.Create(FIndex, FEnsureUnit);
  try
    if Assigned(FNamespaces) then
    begin
      mResolver.Namespaces := FNamespaces();
    end;
    for mFileName in TLspEventHandlers.SourceFiles(FIndex, AFiles) do
    begin
      if FReadText(mFileName, mText) then
      begin
        CollectFile(mResolver, mFileName, mText, AClasses, Result, AUnresolved);
      end;
    end;
  finally
    mResolver.Free;
  end;
end;

function TLspDataAccessSites.Execute(const AArguments: TJSONArray): TJSONValue;
var
  mFileName: string;
  mSource: TLspMetricsSource;
  mClasses: TArray<TDataAccessClass>;
  mSites: TArray<TDataAccessSite>;
  mUnresolved: Integer;
begin
  mFileName := '';
  mClasses := nil;
  if (AArguments <> nil) and (AArguments.Count > 0) and (AArguments.Items[0] is TJSONString) then
  begin
    mFileName := TDocumentUris.ToPath(AArguments.Items[0].Value);
  end;
  if (AArguments <> nil) and (AArguments.Count > 1) then
  begin
    mClasses := ParseClasses(AArguments.Items[1]);
  end;
  if not (Assigned(FSourceFor) and FSourceFor(mFileName, True, mSource)) then
  begin
    mSource := Default(TLspMetricsSource);
  end;
  mSites := Collect(mSource.Files, mClasses, mUnresolved);
  Result := TJSONObject.ParseJSONValue(ToJson(mSites, mUnresolved));
end;

class function TLspDataAccessSites.ParseClasses(AValue: TJSONValue): TArray<TDataAccessClass>;
var
  mItem: TJSONValue;
  mClass: TDataAccessClass;
begin
  Result := nil;
  if not (AValue is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(AValue) do
  begin
    if not (mItem is TJSONObject) then
    begin
      Continue;
    end;
    mClass := Default(TDataAccessClass);
    mClass.Name := TJsonRead.TrimmedText(TJSONObject(mItem), 'name');
    mClass.Kind := TJsonRead.TrimmedText(TJSONObject(mItem), 'kind');
    mClass.Methods := TJsonRead.TrimmedStrings(TJsonRead.Value(TJSONObject(mItem), 'methods'));
    if (mClass.Name <> '') and (Length(mClass.Methods) > 0) then
    begin
      Result := Result + [mClass];
    end;
  end;
end;

function SiteJson(const ASite: TDataAccessSite): TJSONObject;
var
  mArguments: TJSONArray;
  mArgument: string;
begin
  Result := TJSONObject.Create;
  Result.AddPair('file', ASite.FileName);
  Result.AddPair('line', TJSONNumber.Create(ASite.Position.Line));
  Result.AddPair('character', TJSONNumber.Create(ASite.Position.Character));
  Result.AddPair('breakLine', TJSONNumber.Create(ASite.BreakLine));
  Result.AddPair('class', ASite.WatchedClass);
  Result.AddPair('kind', ASite.Kind);
  Result.AddPair('method', ASite.Method);
  Result.AddPair('receiver', ASite.Receiver);
  Result.AddPair('receiverType', ASite.ReceiverType);
  mArguments := TJSONArray.Create;
  Result.AddPair('arguments', mArguments);
  for mArgument in ASite.Arguments do
  begin
    mArguments.Add(mArgument);
  end;
  Result.AddPair('routine', ASite.Routine);
end;

class function TLspDataAccessSites.ToJson(const ASites: TArray<TDataAccessSite>; AUnresolved: Integer): string;
var
  mRoot: TJSONObject;
  mList: TJSONArray;
  mSite: TDataAccessSite;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('format', TJSONNumber.Create(1));
    mList := TJSONArray.Create;
    mRoot.AddPair('sites', mList);
    for mSite in ASites do
    begin
      mList.AddElement(SiteJson(mSite));
    end;
    mRoot.AddPair('unresolved', TJSONNumber.Create(AUnresolved));
    Result := mRoot.ToJSON([]);
  finally
    mRoot.Free;
  end;
end;

end.
