unit Atlas.Common.Lsp.Documentation;

// XMLDoc für Hover, Parameter-Hint und Vervollständigung (#654).
//
// Load liest den ///-Kommentar über einer Deklaration (TXmlDoc) und löst
// <inheritdoc/> auf: ohne cref über den überschriebenen Member im nächsten
// Vorfahren bzw. in implementierten Interfaces, bei Typen über den Vorfahrtyp;
// mit cref über das genannte Symbol. Eigene Abschnitte gehen vor, fehlende
// kommen vom Vorfahren (TXmlDoc.Inherit), auch über mehrere Stufen.
//
// ToJson gibt die Abschnitte strukturiert aus: je Abschnitt Art, Name und
// Teilstücke. Verweise (cref) tragen den Fundort des Ziels (name, unit, file,
// line, character), damit das Plugin sie wie die Typnamen der Deklaration
// anklickbar macht (#588). HintsJson gibt die Anzeige-Einstellungen "hints"
// des Projekts an das Plugin weiter (atlas.json vor den Plugin-Einstellungen).

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Pascal.XmlDoc;

type
  /// <summary>Liefert den Text einer Datei; False, wenn sie nicht lesbar ist.</summary>
  TDocReadText = reference to function(const AFileName: string; out AText: string): Boolean;

  /// <summary>Einstellungen "hints" für das Dokument AUri (#654).</summary>
  TDocHintsProvider = reference to function(const AUri: string): THintSettings;

  /// <summary>Fundort eines cref (0-basiert, Position des Namens).</summary>
  TDocTarget = record
    Cref: string;
    Name: string;
    UnitName: string;
    FileName: string;
    Line: Integer;
    Character: Integer;
  end;

  TLspDocumentation = class
  public const
    /// <summary>Höchstens so viele Stufen inheritdoc hintereinander.</summary>
    MaxInheritDepth = 8;
  private type
    TLoader = class
    private
      FResolver: TNameResolver;
      FReadText: TDocReadText;
      FLines: TDictionary<string, TArray<string>>;
      function LinesOf(const AFileName: string; out ALines: TArray<string>): Boolean;
      function DocOf(const ASymbol: TResolvedSymbol; ADepth: Integer): TXmlDoc;
      function AncestorDoc(const ASymbol: TResolvedSymbol; ADepth: Integer): TXmlDoc;
      function Resolve(const ASymbol: TResolvedSymbol; const ADoc: TXmlDoc; ADepth: Integer): TXmlDoc;
    public
      constructor Create(AResolver: TNameResolver; const AReadText: TDocReadText);
      destructor Destroy; override;
    end;
  public
    /// <summary>Kommentar über ALine (0-basiert) in ALines. Ist ASymbol gesetzt (Found) und steht
    /// &lt;inheritdoc/&gt; im Kommentar, kommt die Doku des Vorfahren bzw. des cref-Ziels dazu; AReadText
    /// liest deren Dateien.</summary>
    class function Load(AResolver: TNameResolver; const ASymbol: TResolvedSymbol; const ALines: TArray<string>;
      ALine: Integer; const AReadText: TDocReadText): TXmlDoc; static;
    /// <summary>Fundorte aller cref in ADoc (Verweise und Exceptions), von AFromUnit bzw. AContainer aus
    /// aufgelöst; nicht auflösbare fehlen.</summary>
    class function Targets(AResolver: TNameResolver; const AFromUnit: TUnitIndex; const AContainer: string;
      const ADoc: TXmlDoc): TArray<TDocTarget>; static;
    /// <summary>Abschnitte und Teilstücke als JSON; Verweise mit Eintrag in ATargets tragen ihren Fundort.</summary>
    class function ToJson(const ADoc: TXmlDoc; const ATargets: TArray<TDocTarget>): TJSONObject; static;
    /// <summary>Anzeige-Einstellungen für das Plugin: {"full": …, "maxLines": …} (#654).</summary>
    class function HintsJson(const AHints: THintSettings): TJSONObject; static;
    /// <summary>Liest AOwnFile aus AOwnText (Editorinhalt, auch ungespeichert), andere Dateien über AReadText.</summary>
    class function Reader(const AOwnFile, AOwnText: string; const AReadText: TDocReadText): TDocReadText; static;
    /// <summary>Text in Zeilen (CRLF, LF oder CR); wie TTextLines.SplitLines.</summary>
    class function SplitLines(const AText: string): TArray<string>; static;
  end;

implementation

uses
  Atlas.Text.Lines;

{ TLspDocumentation.TLoader }

constructor TLspDocumentation.TLoader.Create(AResolver: TNameResolver; const AReadText: TDocReadText);
begin
  inherited Create;
  FResolver := AResolver;
  FReadText := AReadText;
  FLines := TDictionary<string, TArray<string>>.Create;
end;

destructor TLspDocumentation.TLoader.Destroy;
begin
  FLines.Free;
  inherited;
end;

function TLspDocumentation.TLoader.LinesOf(const AFileName: string; out ALines: TArray<string>): Boolean;
var
  Text: string;
begin
  if FLines.TryGetValue(UpperCase(AFileName), ALines) then
    Exit(True);
  Result := Assigned(FReadText) and FReadText(AFileName, Text);
  if not Result then
    Exit;
  ALines := TLspDocumentation.SplitLines(Text);
  FLines.AddOrSetValue(UpperCase(AFileName), ALines);
end;

function TLspDocumentation.TLoader.DocOf(const ASymbol: TResolvedSymbol; ADepth: Integer): TXmlDoc;
var
  Lines: TArray<string>;
begin
  Result := Default(TXmlDoc);
  if (ASymbol.FileName = '') or not LinesOf(ASymbol.FileName, Lines) then
    Exit;
  Result := TXmlDoc.Parse(TXmlDoc.CommentAbove(Lines, ASymbol.Range.StartPos.Line));
  if Result.InheritDoc then
    Result := Resolve(ASymbol, Result, ADepth);
end;

function TLspDocumentation.TLoader.AncestorDoc(const ASymbol: TResolvedSymbol; ADepth: Integer): TXmlDoc;
var
  OwnerUnit, TypeUnit: TUnitIndex;
  Owner, Base, Candidate: TResolvedSymbol;
  Bases: TArray<TResolvedSymbol>;
  Index: Integer;
  IsType: Boolean;
begin
  Result := Default(TXmlDoc);
  if ADepth > TLspDocumentation.MaxInheritDepth then
    Exit;
  IsType := ASymbol.Container = '';
  if IsType then
  begin
    if not ASymbol.IsType then
      Exit;
    Owner := ASymbol;
  end
  else if not (FResolver.DeclaringUnit(ASymbol, OwnerUnit) and
    FResolver.ResolveTypeFrom(OwnerUnit, ASymbol.Container, Owner)) then
    Exit;
  // Vorfahr zuerst, dann die implementierten Interfaces.
  Bases := nil;
  // Helfer: nur der Vorfahr-Helfer (#848); der Zieltyp am Ende von Ancestors ist kein Vorfahr.
  if Owner.SymbolKind = TIndexSymbolKind.HelperType then
  begin
    if FResolver.HelperParent(Owner, Base) then
      Bases := [Base];
  end
  else if FResolver.AncestorOf(Owner, Base) then
    Bases := Bases + [Base];
  if (Owner.SymbolKind <> TIndexSymbolKind.HelperType) and FResolver.DeclaringUnit(Owner, TypeUnit) then
    for Index := 1 to High(Owner.Ancestors) do
      if FResolver.ResolveTypeFrom(TypeUnit, Owner.Ancestors[Index], Base) then
        Bases := Bases + [Base];
  for Base in Bases do
  begin
    if IsType then
      Candidate := Base
    else if not FResolver.DeclaredMember(Base, ASymbol.Name, Candidate) then
      Continue;
    Result := DocOf(Candidate, ADepth + 1);
    // Ohne eigene Doku dort weiter oben suchen.
    if Result.IsEmpty then
      Result := AncestorDoc(Candidate, ADepth + 1);
    if not Result.IsEmpty then
      Exit;
  end;
end;

function TLspDocumentation.TLoader.Resolve(const ASymbol: TResolvedSymbol; const ADoc: TXmlDoc;
  ADepth: Integer): TXmlDoc;
var
  FromUnit: TUnitIndex;
  Target: TResolvedSymbol;
  Base: TXmlDoc;
begin
  Base := Default(TXmlDoc);
  if ADepth <= TLspDocumentation.MaxInheritDepth then
    if ADoc.InheritCref <> '' then
    begin
      if FResolver.DeclaringUnit(ASymbol, FromUnit) and
        FResolver.LocateCref(FromUnit, ASymbol.Container, ADoc.InheritCref, Target) then
        Base := DocOf(Target, ADepth + 1);
    end
    else
      Base := AncestorDoc(ASymbol, ADepth);
  Result := ADoc.Inherit(Base);
end;

{ TLspDocumentation }

class function TLspDocumentation.SplitLines(const AText: string): TArray<string>;
begin
  Result := TTextLines.SplitLines(AText);
end;

class function TLspDocumentation.HintsJson(const AHints: THintSettings): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('expand', AHints.XmlDocExpand);
  Result.AddPair('maxLines', TJSONNumber.Create(AHints.XmlDocMaxLines));
end;

class function TLspDocumentation.Reader(const AOwnFile, AOwnText: string;
  const AReadText: TDocReadText): TDocReadText;
begin
  Result :=
    function(const AName: string; out AText: string): Boolean
    begin
      if SameText(AName, AOwnFile) then
      begin
        AText := AOwnText;
        Exit(True);
      end;
      Result := Assigned(AReadText) and AReadText(AName, AText);
    end;
end;

class function TLspDocumentation.Load(AResolver: TNameResolver; const ASymbol: TResolvedSymbol;
  const ALines: TArray<string>; ALine: Integer; const AReadText: TDocReadText): TXmlDoc;
var
  Loader: TLoader;
begin
  Result := TXmlDoc.Parse(TXmlDoc.CommentAbove(ALines, ALine));
  if not Result.InheritDoc or (AResolver = nil) or not ASymbol.Found then
    Exit;
  Loader := TLoader.Create(AResolver, AReadText);
  try
    Result := Loader.Resolve(ASymbol, Result, 0);
  finally
    Loader.Free;
  end;
end;

class function TLspDocumentation.Targets(AResolver: TNameResolver; const AFromUnit: TUnitIndex;
  const AContainer: string; const ADoc: TXmlDoc): TArray<TDocTarget>;
var
  Seen: TDictionary<string, Boolean>;
  Section: TXmlDocSection;
  Run: TXmlDocRun;

  procedure Add(const ACref: string);
  var
    Symbol: TResolvedSymbol;
    Target: TDocTarget;
  begin
    if (ACref = '') or Seen.ContainsKey(ACref) then
      Exit;
    Seen.Add(ACref, True);
    if not AResolver.LocateCref(AFromUnit, AContainer, ACref, Symbol) then
      Exit;
    Target.Cref := ACref;
    Target.Name := Symbol.Name;
    Target.UnitName := Symbol.UnitName;
    Target.FileName := Symbol.FileName;
    Target.Line := Symbol.SelectionRange.StartPos.Line;
    Target.Character := Symbol.SelectionRange.StartPos.Character;
    Result := Result + [Target];
  end;

begin
  Result := nil;
  if AResolver = nil then
    Exit;
  Seen := TDictionary<string, Boolean>.Create;
  try
    for Section in ADoc.Sections do
    begin
      if Section.Kind = TXmlDocSectionKind.Exception then
        Add(Section.Name);
      for Run in Section.Runs do
        if Run.Kind = TXmlDocRunKind.Ref then
          Add(Run.Target);
    end;
  finally
    Seen.Free;
  end;
end;

function FindTarget(const ATargets: TArray<TDocTarget>; const ACref: string; out ATarget: TDocTarget): Boolean;
var
  Target: TDocTarget;
begin
  for Target in ATargets do
    if Target.Cref = ACref then
    begin
      ATarget := Target;
      Exit(True);
    end;
  Result := False;
end;

procedure AddLocation(AObject: TJSONObject; const ATarget: TDocTarget);
begin
  AObject.AddPair('name', ATarget.Name);
  if ATarget.UnitName <> '' then
    AObject.AddPair('unit', ATarget.UnitName);
  AObject.AddPair('file', ATarget.FileName);
  AObject.AddPair('line', TJSONNumber.Create(ATarget.Line));
  AObject.AddPair('character', TJSONNumber.Create(ATarget.Character));
end;

class function TLspDocumentation.ToJson(const ADoc: TXmlDoc; const ATargets: TArray<TDocTarget>): TJSONObject;
var
  Sections, Runs: TJSONArray;
  Section: TXmlDocSection;
  Run: TXmlDocRun;
  Item, RunItem, RefItem: TJSONObject;
  Target: TDocTarget;
begin
  Result := TJSONObject.Create;
  Sections := TJSONArray.Create;
  Result.AddPair('sections', Sections);
  for Section in ADoc.Sections do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('kind', TXmlDoc.SectionName(Section.Kind));
    if Section.Name <> '' then
      Item.AddPair('name', Section.Name);
    if (Section.Kind = TXmlDocSectionKind.Exception) and FindTarget(ATargets, Section.Name, Target) then
    begin
      RefItem := TJSONObject.Create;
      AddLocation(RefItem, Target);
      Item.AddPair('ref', RefItem);
    end;
    Runs := TJSONArray.Create;
    for Run in Section.Runs do
    begin
      RunItem := TJSONObject.Create;
      RunItem.AddPair('kind', TXmlDoc.RunKindName(Run.Kind));
      if Run.Text <> '' then
        RunItem.AddPair('text', Run.Text);
      if Run.Target <> '' then
        RunItem.AddPair('target', Run.Target);
      if TXmlDocStyle.Bold in Run.Styles then
        RunItem.AddPair('bold', TJSONTrue.Create);
      if TXmlDocStyle.Italic in Run.Styles then
        RunItem.AddPair('italic', TJSONTrue.Create);
      if Run.Level > 0 then
        RunItem.AddPair('level', TJSONNumber.Create(Run.Level));
      if (Run.Kind = TXmlDocRunKind.Ref) and FindTarget(ATargets, Run.Target, Target) then
        AddLocation(RunItem, Target);
      Runs.AddElement(RunItem);
    end;
    Item.AddPair('runs', Runs);
    Sections.AddElement(Item);
  end;
end;

end.
