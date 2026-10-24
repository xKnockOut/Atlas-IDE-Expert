unit Atlas.Common.Architecture.UsesLocator;

// Fundstellen der Kanten des Uses-Graphen (#268): Zeile und Spalte des
// uses-Eintrags in der Datei der verwendenden Unit.
//
// - Gelesen wird erst bei Bedarf (Zyklen, Querverbindungen, Sprung aus dem
//   Fenster), damit der Graph klein bleibt.
// - Inaktive {$IFDEF}-Zweige werden mit den Defines der Datei ausgeblendet,
//   bevor die Einträge gesucht werden; so trifft ein Name, der in zwei
//   Zweigen steht, den geltenden.
// - Die Einträge liefert TUsesClauses.References, dieselbe Quelle, aus der
//   die Architekturregeln (#183) ihre uses lesen.
// - Je Datei und Stand (Hash des Graphknotens) wird einmal gelesen.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Architecture.UsesGraph;

type
  /// <summary>Liest den Text einer Datei (Editor-Stand oder Platte); False, wenn sie fehlt.</summary>
  TUsesTextReader = reference to function(const AFileName: string; out AText: string): Boolean;
  /// <summary>Aktive Defines für die Datei; nil = keine.</summary>
  TUsesDefinesFunc = reference to function(const AFileName: string): TArray<string>;

  TUsesLocation = record
    FileName: string;
    /// <summary>Bereich des Namens im uses, Zeilen und Spalten ab 0.</summary>
    Range: TTextRange;
  end;

  TUsesLocator = class
  private
    FReader: TUsesTextReader;
    FDefines: TUsesDefinesFunc;
    /// <summary>Datei in Kleinschreibung + '|' + Hash → Einträge.</summary>
    FCache: TDictionary<string, TArray<TUsesReference>>;
    function ReferencesOf(const ANode: TUsesNode): TArray<TUsesReference>;
  public
    constructor Create(const AReader: TUsesTextReader; const ADefines: TUsesDefinesFunc);
    destructor Destroy; override;
    /// <summary>Einträge aus den uses-Listen (ohne requires/contains) von AText, inaktive Zweige ausgeblendet.</summary>
    class function UsesReferences(const AText: string; const ADefines: TArray<string>): TArray<TUsesReference>; static;
    /// <summary>Fundstelle der Kante; False, wenn die Datei fehlt oder der Eintrag nicht (mehr) dort steht.</summary>
    function Locate(AGraph: TUsesGraph; const AEdge: TUsesEdge; out ALocation: TUsesLocation): Boolean;
  end;

implementation

uses
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Index.Extractor;

{ TUsesLocator }

constructor TUsesLocator.Create(const AReader: TUsesTextReader; const ADefines: TUsesDefinesFunc);
begin
  inherited Create;
  FReader := AReader;
  FDefines := ADefines;
  FCache := TDictionary<string, TArray<TUsesReference>>.Create;
end;

destructor TUsesLocator.Destroy;
begin
  FCache.Free;
  inherited;
end;

class function TUsesLocator.UsesReferences(const AText: string; const ADefines: TArray<string>): TArray<TUsesReference>;
var
  Reference: TUsesReference;
begin
  Result := nil;
  for Reference in TUsesClauses.References(TPascalLexer.Tokenize(TIndexExtractor.BlankInactive(AText, ADefines))) do
    if Reference.List = TUsesListKind.UsesList then
      Result := Result + [Reference];
end;

function TUsesLocator.ReferencesOf(const ANode: TUsesNode): TArray<TUsesReference>;
var
  Key, Text: string;
  Defines: TArray<string>;
begin
  Key := LowerCase(ANode.FileName) + '|' + ANode.Hash;
  if FCache.TryGetValue(Key, Result) then
    Exit;
  Result := nil;
  if Assigned(FReader) and FReader(ANode.FileName, Text) then
  begin
    Defines := nil;
    if Assigned(FDefines) then
      Defines := FDefines(ANode.FileName);
    Result := UsesReferences(Text, Defines);
  end;
  FCache.AddOrSetValue(Key, Result);
end;

function TUsesLocator.Locate(AGraph: TUsesGraph; const AEdge: TUsesEdge; out ALocation: TUsesLocation): Boolean;
var
  Node: TUsesNode;
  Reference: TUsesReference;
  InInterface: Boolean;
  Order: Integer;
begin
  ALocation := Default(TUsesLocation);
  Node := AGraph.Node(AEdge.Source);
  ALocation.FileName := Node.FileName;
  InInterface := AEdge.Section = TUsesSection.Interface_;
  // Zuerst derselbe Name im selben Abschnitt an derselben Stelle der Liste, sonst der erste mit dem Namen.
  Order := 0;
  for Reference in ReferencesOf(Node) do
  begin
    if Reference.InInterface <> InInterface then
      Continue;
    if SameText(Reference.Name, AEdge.Name) and (Order = AEdge.Order) then
    begin
      ALocation.Range := Reference.Range;
      Exit(True);
    end;
    Inc(Order);
  end;
  for Reference in ReferencesOf(Node) do
    if (Reference.InInterface = InInterface) and SameText(Reference.Name, AEdge.Name) then
    begin
      ALocation.Range := Reference.Range;
      Exit(True);
    end;
  Result := False;
end;

end.
