unit Atlas.Common.Lsp.CompletionRequest;

// Anfrage der Vervollständigung (Code-Review S-01, Konzept 4.2 Schritt 4): alles, was die Fälle von
// textDocument/completion je Anfrage brauchen, in einem Objekt statt in neun Parametern. Einmal
// berechnete Werte (Zeilen, Zeilenende, Index der eigenen Unit) bleiben im Objekt. Dazu die Typen der
// Vervollständigung (Kontext, Eintrag, Liste), die Atlas.Common.Lsp.Completion unter ihrem Namen
// weiter anbietet.
//
// Die Zeilenhelfer behalten bewusst die Semantik der früheren freien Funktionen (LineBefore, LineOf,
// TextLines, OffsetOf): Zeilen werden an #10 getrennt, ein #13 davor fällt weg; LineBefore endet auch an
// einem einzelnen #13. Sie lesen deshalb immer den Text, auch wenn ein Dokument vorliegt.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.Documentation;

type
  TCompletionContextKind = (None, Scope, Member, UsesClause);
  /// <summary>Einschränkung der Kandidaten im Gültigkeitsbereich (#31).</summary>
  TCompletionFilter = (Any, Types, InheritedCall);
  /// <summary>Stelle im Quelltext für passende Schlüsselwörter (#31).</summary>
  TCompletionPlace = (Unknown, Declaration, ClassBody, Statement);

  TCompletionContext = record
    Kind: TCompletionContextKind;
    /// <summary>Schon getippter Anfang des Namens.</summary>
    Prefix: string;
    /// <summary>Kette vor dem Punkt bei Member, z. B. ['Self', 'Liste'].</summary>
    Names: TArray<string>;
    /// <summary>Offset, an dem die Namen gelten.</summary>
    Offset: Integer;
    /// <summary>Bei Member: Anfang der Kette und Position des Punkts.</summary>
    ChainStart: TTextPosition;
    DotPos: TTextPosition;
    /// <summary>Bei Member: Das letzte Glied steht mit Klammern da, Foo(1). oder TFoo(X). (#188).</summary>
    Called: Boolean;
    /// <summary>Bei Scope: nur Typen bzw. nur Methoden der Vorfahren (#31).</summary>
    Filter: TCompletionFilter;
    /// <summary>Bei Filter Types: auch Typ-Schlüsselwörter wie string und array (nach ":").</summary>
    TypeKeywords: Boolean;
    /// <summary>Bei Scope: Anweisung, Deklaration oder Klassenrumpf (#31).</summary>
    Place: TCompletionPlace;
    /// <summary>Typargument nach "TFoo&lt;" (#450): Position des Typnamens und aktiver Typparameter (0-basiert).
    /// Collect löscht Generic wieder, wenn der Name kein generischer Typ ist.</summary>
    Generic: Boolean;
    GenericOwnerPos: TTextPosition;
    GenericParam: Integer;
  end;

  TCompletionItem = record
    Name: string;
    Detail: string;
    /// <summary>CompletionItemKind des LSP.</summary>
    Kind: Integer;
    /// <summary>Text für den Filter des Editors; '' = Name.</summary>
    FilterText: string;
    /// <summary>Weitere Änderungen beim Annehmen, z. B. der uses-Eintrag.</summary>
    AdditionalEdits: TArray<TRuleEdit>;
    /// <summary>Datei und Namensposition der Deklaration für completionItem/resolve; '' ohne.</summary>
    SourceFile: string;
    SourcePosition: TTextPosition;
    /// <summary>Deklarierender Typ bei Mitgliedern (#419); ''.</summary>
    Container: string;
    /// <summary>Vererbungstiefe bei Mitgliedern: 0 = eigener Typ (#419).</summary>
    Depth: Integer;
    /// <summary>Mitglied aus einem Helper (#456).</summary>
    IsHelper: Boolean;
    /// <summary>Namenspositionen weiterer Überladungen in SourceFile (#425).</summary>
    Overloads: TArray<TTextPosition>;
    /// <summary>Routine mit Parametern (in irgendeiner Überladung), für Klammern beim Übernehmen (#430).</summary>
    HasParameters: Boolean;
    /// <summary>Text beim Übernehmen statt des Namens; ''.</summary>
    InsertText: string;
    /// <summary>Erwarteter Typ an der Stelle (#417, #444); '' ohne. Atlas gruppiert dann nach Fits.</summary>
    Expected: string;
    /// <summary>Eintrag passt zu Expected.</summary>
    Fits: Boolean;
    /// <summary>Bedingung der Deklaration ("WIN64", "platform"); '' = immer (#476).</summary>
    Condition: string;
    /// <summary>Unter der aktiven Konfiguration nicht deklariert; Atlas zeigt es abgeschwächt am Ende (#476).</summary>
    Unavailable: Boolean;
    /// <summary>Gültigkeitsbereich ohne Punkt davor (#488): 1 lokal, 2 Parameter, 3 Mitglied von Self,
    /// 4 eigene Unit, 5 andere Unit; 0 = keine Angabe (nach einem Punkt, Schlüsselwörter …).</summary>
    Scope: Integer;
    /// <summary>Unit der Deklaration bei Scope 5 (#488): Atlas zeigt sie als Tag.</summary>
    UnitName: string;
    /// <summary>Verdeckte gleichnamige Deklarationen weiter außen (#488), z. B. "Feld TKunde.Total".</summary>
    Hides: TArray<string>;
    /// <summary>Eintrag erzeugt Code statt nur einen Namen: 'override' (#443), 'create' (neue Methode, #444);
    /// Atlas wertet AdditionalEdits dann nicht als uses-Ergänzung.</summary>
    Action: string;
    /// <summary>Ersetzt TextEdit.Range statt nur den getippten Namen (Postfix-Vorlagen, #188).</summary>
    HasTextEdit: Boolean;
    TextEdit: TRuleEdit;
    /// <summary>Wert einer Aufzählung (#448): Stelle in der Deklaration ab 1; 0 bei anderen Einträgen.</summary>
    Ordinal: Integer;
    /// <summary>Mengenmodus (#448): Aufzählungstyp der Menge; '' sonst. Dann gelten SetChecked und SetRange.</summary>
    SetOf: string;
    /// <summary>Wert steht schon in der Klammer.</summary>
    SetChecked: Boolean;
    /// <summary>Was Enter mit dem neuen Klammerinhalt ersetzt: von "[" bis hinter "]".</summary>
    SetRange: TTextRange;
    /// <summary>Steht immer oben und passt zu jedem getippten Wort („Alle Werte einfügen“, #449).</summary>
    Pinned: Boolean;
    /// <summary>Zahl als Tag (fehlende Werte, #449); 0 ohne.</summary>
    Count: Integer;
    /// <summary>Eintrag deklariert diesen unbekannten Namen (#471); Atlas zeigt die Gruppe „Name ist unbekannt“.</summary>
    Unknown: string;
    /// <summary>Interface implementieren (#466): Eintrag der Liste mit Kontrollkästchen (SetOf = Interfaces,
    /// SetChecked, SetRange = getipptes Wort). Atlas übernimmt die AdditionalEdits aller angehakten Einträge in
    /// Ordinal-Reihenfolge und fasst Einfügungen an derselben Stelle zusammen.</summary>
    Batch: Boolean;
    /// <summary>Hinweis „3 Methoden von IExporter fehlen“ (#466): ganz oben, nie vorgewählt.</summary>
    Hint: Boolean;
    /// <summary>Komponente aus dem Formular (#455): Name des Formulars; Atlas zeigt die Gruppe „Formular …“ oben.</summary>
    Form: string;
    /// <summary>Komponente passt nur über ihren Typ ("button" → btnSave: TButton), nicht über den Namen.</summary>
    ByType: Boolean;
    /// <summary>Sender mit Typumwandlung (#480): Typ, als der Sender gilt; '' sonst. Dann ersetzt TextEdit
    /// "Sender.Na" durch "(Sender as TButton).Name".</summary>
    Sender: string;
    /// <summary>Komponenten, denen die Methode im Designer zugewiesen ist: "btnSave, btnLoad".</summary>
    SenderOf: string;
    /// <summary>Feld- oder Parametername (#461): Datenmenge, aus der der Name stammt; '' sonst.</summary>
    DataSet: string;
    /// <summary>Kurzform der SQL-Anweisung als Quellenangabe für die Fußzeile; '' ohne Anweisung.</summary>
    DataSource: string;
    /// <summary>Freigabe absichern (#489): 'newLine' oder 'routineEnd'; '' sonst. Weitertippen verwirft.</summary>
    Guard: string;
    /// <summary>InsertText bzw. TextEdit.NewText ist ein LSP-Snippet mit Platzhaltern (#51); dann
    /// insertTextFormat = 2. Nur an Clients mit snippetSupport.</summary>
    Snippet: Boolean;
    /// <summary>Auch die AdditionalEdits sind LSP-Snippets; gleiche Nummern sind mit denen des Haupttexts verknüpft
    /// (resourcestring auslagern, #473: der Name im Abschnitt und an der Stelle).</summary>
    LinkedEdits: Boolean;
    /// <summary>Befehl, den der Client nach dem Übernehmen über workspace/executeCommand ausführt; '' ohne.</summary>
    Command: string;
    CommandTitle: string;
    CommandArguments: TArray<string>;
    /// <summary>Typargument (#450): Typparameter ("T"), sein Constraint ("class, constructor"), der Code der
    /// Erklärung (classes, values, constructible, implements:IFoo, descends:TBasis) und die ausgeblendeten Arten
    /// (classes, records, interfaces, enums, basic, durch Kommas getrennt); '' sonst.</summary>
    TypeParam: string;
    Constraint: string;
    ConstraintHint: string;
    HiddenKinds: string;
    /// <summary>Gebundene Typparameter des umgebenden Typs ("T=TKunde", #450); Detail ist schon eingesetzt,
    /// completionItem/resolve setzt sie in Deklaration und Dokumentation ein.</summary>
    Bindings: TArray<string>;
    /// <summary>Typkonvertierung (#490): Umwandlungseintrag in diesen erwarteten Typ ("string"), Name ist der
    /// gezeigte Ausdruck (Count.ToString), TextEdit setzt die ganze Kette ein; ConvertFrom ist der Name des
    /// Originals, vor dem Atlas ihn zeigt. '' bei anderen Einträgen.</summary>
    Conversion: string;
    ConvertFrom: string;
    /// <summary>Gleitkommawert für eine Ganzzahl (#490): sein Typ ("Double"); Atlas weist im Detailpanel auf
    /// Round und Trunc hin. '' sonst.</summary>
    Lossy: string;
  end;

  TCompletionItems = record
    Items: TArray<TCompletionItem>;
    /// <summary>Liste wurde gekürzt; der Editor fragt beim Weitertippen neu.</summary>
    Incomplete: Boolean;
  end;

  /// <summary>Teilergebnis einer gestaffelten Vervollständigung (#616), in Anzeigereihenfolge.</summary>
  TCompletionPartialProc = reference to procedure(const AItems: TArray<TCompletionItem>);

  TCompletionReadText = TDocReadText;

  /// <summary>Alles, was die Fälle der Vervollständigung je Anfrage brauchen (Code-Review S-01, 4.2 Schritt 4).
  /// Der Aufrufer besitzt das Objekt (try … finally Free); Baum, Resolver und Index gehören ihm nicht.
  /// Einmal berechnete Werte (Zeilen, Index der eigenen Unit) bleiben im Objekt.</summary>
  TCompletionRequest = class
  private
    FText: string;
    FFileName: string;
    FUri: string;
    FPosition: TTextPosition;
    FTree: TSyntaxTree;
    FResolver: TNameResolver;
    FIndex: ISymbolIndex;
    FReadText: TCompletionReadText;
    FMatching: TCompletionMatching;
    FSettings: TCompletionSettings;
    FTrigger: string;
    FLines: TArray<string>;
    FLinesReady: Boolean;
    FUnitIndex: TUnitIndex;
    FUnitIndexReady: Boolean;
    procedure SetTree(AValue: TSyntaxTree);
    procedure SetResolver(AValue: TNameResolver);
  public
    /// <summary>Aus einem offenen Dokument (Handle); liest dessen Text einmal.</summary>
    constructor Create(const ADocument: ITextDocument; const AFileName: string;
      const APosition: TTextPosition); overload;
    /// <summary>Aus Text (Tests und Kompatibilitäts-Überladungen). Matching unscharf, Settings Standard.</summary>
    constructor Create(const AText, AFileName: string; const APosition: TTextPosition); overload;
    /// <summary>Zeile ALine ohne Zeilenende; '' außerhalb.</summary>
    function LineText(ALine: Integer): string;
    /// <summary>Zeile der Position bis zum Cursor; endet am Zeilenende (#10 oder #13).</summary>
    function LineBefore: string;
    /// <summary>Alle Zeilen ohne Zeilenende, einmal geteilt.</summary>
    function Lines: TArray<string>;
    /// <summary>Offset (0-basiert) von APosition im Text; Zeilen zählen an #10, das Zeichen wird nicht
    /// begrenzt.</summary>
    function OffsetAt(const APosition: TTextPosition): Integer;
    /// <summary>#13#10, wenn der Text irgendwo CRLF enthält, sonst #10.</summary>
    function LineBreak: string;
    /// <summary>Index der eigenen Unit aus dem Baum (Resolver.ExtractedUnit), einmal je Baum und Resolver.
    /// </summary>
    function UnitIndex: TUnitIndex;
    /// <summary>Text des Dokuments.</summary>
    property Text: string read FText;
    property FileName: string read FFileName;
    property Position: TTextPosition read FPosition;
    /// <summary>URI des Dokuments für Einstellungen je Dokument; '' ohne.</summary>
    property Uri: string read FUri write FUri;
    property Tree: TSyntaxTree read FTree write SetTree;
    property Resolver: TNameResolver read FResolver write SetResolver;
    property Index: ISymbolIndex read FIndex write FIndex;
    property ReadText: TCompletionReadText read FReadText write FReadText;
    property Matching: TCompletionMatching read FMatching write FMatching;
    property Settings: TCompletionSettings read FSettings write FSettings;
    /// <summary>context.triggerCharacter der Anfrage; '' ohne.</summary>
    property Trigger: string read FTrigger write FTrigger;
  end;

implementation

uses
  System.Math,
  System.StrUtils;

{ TCompletionRequest }

constructor TCompletionRequest.Create(const ADocument: ITextDocument; const AFileName: string;
  const APosition: TTextPosition);
begin
  Create(ADocument.Text, AFileName, APosition);
  FUri := ADocument.Uri;
end;

constructor TCompletionRequest.Create(const AText, AFileName: string; const APosition: TTextPosition);
begin
  inherited Create;
  FText := AText;
  FFileName := AFileName;
  FPosition := APosition;
  FMatching := TCompletionMatching.Fuzzy;
  FSettings := TCompletionSettings.Default;
end;

procedure TCompletionRequest.SetTree(AValue: TSyntaxTree);
begin
  FTree := AValue;
  FUnitIndexReady := False;
end;

procedure TCompletionRequest.SetResolver(AValue: TNameResolver);
begin
  FResolver := AValue;
  FUnitIndexReady := False;
end;

function TCompletionRequest.Lines: TArray<string>;
var
  Index: Integer;
begin
  if not FLinesReady then
  begin
    FLines := nil;
    FLines := FText.Split([#10]);
    for Index := 0 to High(FLines) do
      if FLines[Index].EndsWith(#13) then
        FLines[Index] := Copy(FLines[Index], 1, Length(FLines[Index]) - 1);
    FLinesReady := True;
  end;
  Result := FLines;
end;

function TCompletionRequest.LineText(ALine: Integer): string;
begin
  Lines;
  if (ALine < 0) or (ALine > High(FLines)) then
    Exit('');
  Result := FLines[ALine];
end;

function TCompletionRequest.LineBefore: string;
var
  Line, Start, Stop: Integer;
begin
  Start := 1;
  for Line := 1 to FPosition.Line do
  begin
    Start := PosEx(#10, FText, Start) + 1;
    if Start = 1 then
      Exit('');
  end;
  Stop := Start;
  while (Stop <= Length(FText)) and (FText[Stop] <> #10) and (FText[Stop] <> #13) do
    Inc(Stop);
  Result := Copy(FText, Start, Min(FPosition.Character, Stop - Start));
end;

function TCompletionRequest.OffsetAt(const APosition: TTextPosition): Integer;
var
  Index, Line: Integer;
begin
  Line := 0;
  Index := 1;
  while (Line < APosition.Line) and (Index <= Length(FText)) do
  begin
    if FText[Index] = #10 then
      Inc(Line);
    Inc(Index);
  end;
  Result := Index - 1 + APosition.Character;
end;

function TCompletionRequest.LineBreak: string;
begin
  if Pos(#13#10, FText) > 0 then
    Result := #13#10
  else
    Result := #10;
end;

function TCompletionRequest.UnitIndex: TUnitIndex;
begin
  if not FUnitIndexReady then
  begin
    FUnitIndex := FResolver.ExtractedUnit(FTree, FFileName);
    FUnitIndexReady := True;
  end;
  Result := FUnitIndex;
end;

end.
