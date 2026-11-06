unit Atlas.Common.Lsp.Hover.Info;

// Inhalt eines Hovers (THoverInfo) und seine Darstellungen: Markdown, Klartext
// für Clients ohne Markdown (#175) und die Teile für den Atlas-Tooltip
// (atlas, #442, #588). Gesammelt wird der Inhalt in Atlas.Common.Lsp.Hover.Lookup,
// beantwortet wird die Anfrage in Atlas.Common.Lsp.Hover.

interface

uses
  System.JSON,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Pascal.XmlDoc,
  Atlas.Common.Lsp.Documentation,
  Atlas.Common.Lsp.HoverTypes,
  Atlas.Common.Lsp.PublishedMembers,
  Atlas.Common.Rationale.Contract;

type
  /// <summary>Womit der Hover sucht: Namensauflösung, Index und Lesen anderer Dateien (darf nil sein).</summary>
  THoverSource = record
    Resolver: TNameResolver;
    Index: ISymbolIndex;
    ReadText: TDocReadText;
    class function Create(AResolver: TNameResolver; const AIndex: ISymbolIndex;
      const AReadText: TDocReadText): THoverSource; static;
  end;

  THoverInfo = record
    Declaration: string;
    /// <summary>Dokumentation als Markdown (bei Unit-Namen der Dateiname).</summary>
    Documentation: string;
    /// <summary>XMLDoc der Deklaration samt inheritdoc (#654); leer ohne Kommentar.</summary>
    Doc: TXmlDoc;
    /// <summary>Fundorte der cref-Verweise in Doc.</summary>
    DocTargets: TArray<TDocTarget>;
    /// <summary>Unit der Deklaration, wenn sie nicht die aktuelle ist.</summary>
    UnitName: string;
    /// <summary>Markdown mit published-Properties und Ereignissen bei Klassen; sonst ''.</summary>
    Members: string;
    /// <summary>Dieselben Mitglieder und die Standard-Property strukturiert für den Atlas-Tooltip (#110).</summary>
    PublishedItems: TArray<TPublishedMember>;
    DefaultProperty: string;
    /// <summary>Link zur DocWiki bei RTL- und VCL-Symbolen (#27); sonst ''.</summary>
    DocWikiUrl: string;
    /// <summary>Microsoft-Link und 64-Bit-Hinweis bei Windows-API-Funktionen (#120); sonst ''.</summary>
    WinApi: string;
    /// <summary>Message-Handler der Klasse als Markdown (#36); sonst ''.</summary>
    Messages: string;
    /// <summary>Wert bei Zahlen, Konstanten und Aufzählungswerten (#38); sonst ''.</summary>
    Value: string;
    /// <summary>Hinweis bei deprecated, platform, experimental (#38); sonst ''.</summary>
    Deprecation: string;
    /// <summary>In der Formulardatei gesetzte Werte eines Komponentenfelds (#126); sonst ''.</summary>
    FormValues: string;
    /// <summary>Konstruktoren der Attributklasse auf einem Attribut (#119); sonst ''.</summary>
    Constructors: string;
    /// <summary>Art für Badge und Kopfzeile (#588), siehe TLspHoverTypes.KindOf; '' wenn unbekannt.</summary>
    Kind: string;
    /// <summary>VCL, FMX oder RTL; '' bei eigenen Units.</summary>
    Origin: string;
    /// <summary>Fundort des Namens der Deklaration (0-basiert); FileName '' ohne.</summary>
    FileName: string;
    Line: Integer;
    Character: Integer;
    /// <summary>Typnamen in Declaration mit Fundort.</summary>
    Links: TArray<THoverLink>;
    /// <summary>Typ, dessen Kette Ancestors zeigt: der Typ selbst bzw. bei "class of T" T.</summary>
    ChainOf: string;
    /// <summary>Vererbungskette ab ChainOf aufwärts; leer bei anderen Arten.</summary>
    Ancestors: TArray<THoverTypeRef>;
    /// <summary>Begründungen der Deklaration bzw. Unit (#1123); InfoAt liefert alle aus dem Index, HandleHover
    /// filtert nach den Einstellungen.</summary>
    Rationale: TArray<TRationaleEntry>;
    /// <summary>Dateien im ADR-Ordner für die Verweise in Rationale; leer ohne Ordner.</summary>
    AdrFiles: TArray<string>;
    /// <summary>Neu zugewiesener Name an der Stelle (#712): Ziel wie in highlight.reassigned.targets (locals,
    /// loopVars, valueParams, varParams, fields); '' ohne.</summary>
    ReassignedTarget: string;
    /// <summary>Zahl der schreibenden Stellen und ihre Zeilen (ab 0).</summary>
    ReassignedWrites: Integer;
    ReassignedLines: TArray<Integer>;
    function Found: Boolean;
    function ToMarkdown: string;
    /// <summary>Derselbe Inhalt ohne Markdown-Auszeichnung.</summary>
    function ToPlainText: string;
    /// <summary>Teile für den Atlas-Tooltip (#442): Doku strukturiert in documentation (#654) und als Klartext in
    /// documentationText, Hinweis als Klartext. Der Aufrufer übernimmt das Objekt.</summary>
    function ToAtlasJson: TJSONObject;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.RegularExpressions,
  Atlas.Common.Lsp.Rationale,
  Atlas.Common.Lsp.IdeUnits;

// Entfernt nur die Auszeichnung, die der Hover selbst erzeugt: **fett** (Veraltet,
// Überschriften), *Name*: am Absatzanfang (Parameter) und `Code`. Andere Zeichen aus
// dem Kommentar bleiben stehen, z. B. das * in "(Gallery.Page.*)" (in der IDE gesehen).
function StripMarkdown(const AText: string): string;
begin
  Result := TRegEx.Replace(AText, '\*\*([^*\n]+)\*\*', '$1');
  Result := TRegEx.Replace(Result, '(^|\n)\*([^*\n]+)\*:', '$1$2:');
  Result := TRegEx.Replace(Result, '`([^`\n]*)`', '$1');
end;

/// <summary>AFileName für das Plugin; '' für Ersatz-Units der IDE (atlas-ide:…), die es nicht als Datei gibt:
/// kein Sprungziel.</summary>
function LocationFile(const AFileName: string): string;
begin
  Result := AFileName;
  if TIdeUnits.IsIdePath(AFileName) then
  begin
    Result := '';
  end;
end;

function TypeRefJson(const ARef: THoverTypeRef): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', ARef.Name);
  if ARef.UnitName <> '' then
  begin
    Result.AddPair('unit', ARef.UnitName);
  end;
  Result.AddPair('file', LocationFile(ARef.FileName));
  Result.AddPair('line', TJSONNumber.Create(ARef.Line));
  Result.AddPair('character', TJSONNumber.Create(ARef.Character));
end;

/// <summary>AValue unter AName, wenn nicht leer.</summary>
procedure AddText(AObject: TJSONObject; const AName, AValue: string);
begin
  if AValue <> '' then
  begin
    AObject.AddPair(AName, AValue);
  end;
end;

/// <summary>Doku strukturiert und als Klartext (#654), dahinter die Begründungen als eigene Abschnitte (#1123),
/// auch ohne XMLDoc.</summary>
procedure AddDocumentation(AObject: TJSONObject; const AInfo: THoverInfo);
var
  mDocumentation: TJSONObject;
begin
  mDocumentation := nil;
  if not AInfo.Doc.IsEmpty then
  begin
    mDocumentation := TLspDocumentation.ToJson(AInfo.Doc, AInfo.DocTargets);
    AObject.AddPair('documentation', mDocumentation);
    AObject.AddPair('documentationText', AInfo.Doc.ToPlainText);
  end
  else if AInfo.Documentation <> '' then
  begin
    AObject.AddPair('documentationText', StripMarkdown(AInfo.Documentation));
  end;
  if Length(AInfo.Rationale) = 0 then
  begin
    Exit;
  end;
  if mDocumentation = nil then
  begin
    mDocumentation := TJSONObject.Create;
    mDocumentation.AddPair('sections', TJSONArray.Create);
    AObject.AddPair('documentation', mDocumentation);
  end;
  TLspRationale.AddSections(TJSONArray(mDocumentation.GetValue('sections')), AInfo.Rationale, AInfo.AdrFiles);
end;

/// <summary>Fundort der Deklaration, wenn bekannt.</summary>
procedure AddLocation(AObject: TJSONObject; const AInfo: THoverInfo);
begin
  if LocationFile(AInfo.FileName) <> '' then
  begin
    AObject.AddPair('file', AInfo.FileName);
    AObject.AddPair('line', TJSONNumber.Create(AInfo.Line));
    AObject.AddPair('character', TJSONNumber.Create(AInfo.Character));
  end;
end;

/// <summary>Typverweise in der Deklaration mit Start und Länge.</summary>
procedure AddLinks(AObject: TJSONObject; const ALinks: TArray<THoverLink>);
var
  mLinks: TJSONArray;
  mLink: THoverLink;
  mItem: TJSONObject;
begin
  if Length(ALinks) = 0 then
  begin
    Exit;
  end;
  mLinks := TJSONArray.Create;
  for mLink in ALinks do
  begin
    mItem := TypeRefJson(mLink.Target);
    mItem.AddPair('start', TJSONNumber.Create(mLink.Start));
    mItem.AddPair('length', TJSONNumber.Create(mLink.Length));
    mLinks.AddElement(mItem);
  end;
  AObject.AddPair('links', mLinks);
end;

/// <summary>Vererbungskette ab ChainOf.</summary>
procedure AddAncestors(AObject: TJSONObject; const AInfo: THoverInfo);
var
  mAncestors: TJSONArray;
  mAncestor: THoverTypeRef;
begin
  if Length(AInfo.Ancestors) = 0 then
  begin
    Exit;
  end;
  AObject.AddPair('chainOf', AInfo.ChainOf);
  mAncestors := TJSONArray.Create;
  for mAncestor in AInfo.Ancestors do
  begin
    mAncestors.AddElement(TypeRefJson(mAncestor));
  end;
  AObject.AddPair('ancestors', mAncestors);
end;

/// <summary>Neu zugewiesener Name (#712): Ziel, Zahl der Zuweisungen und ihre Zeilen.</summary>
procedure AddReassigned(AObject: TJSONObject; const AInfo: THoverInfo);
var
  mItem: TJSONObject;
  mWritten: TJSONArray;
  mLine: Integer;
begin
  if AInfo.ReassignedTarget = '' then
  begin
    Exit;
  end;
  mItem := TJSONObject.Create;
  mItem.AddPair('target', AInfo.ReassignedTarget);
  mItem.AddPair('writes', TJSONNumber.Create(AInfo.ReassignedWrites));
  mWritten := TJSONArray.Create;
  for mLine in AInfo.ReassignedLines do
  begin
    mWritten.Add(mLine);
  end;
  mItem.AddPair('lines', mWritten);
  AObject.AddPair('reassigned', mItem);
end;

{ THoverSource }

class function THoverSource.Create(AResolver: TNameResolver; const AIndex: ISymbolIndex;
  const AReadText: TDocReadText): THoverSource;
begin
  Result.Resolver := AResolver;
  Result.Index := AIndex;
  Result.ReadText := AReadText;
end;

{ THoverInfo }

function THoverInfo.Found: Boolean;
begin
  Result := Declaration <> '';
end;

function THoverInfo.ToAtlasJson: TJSONObject;
var
  mMembers: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('declaration', Declaration);
  AddText(Result, 'unit', UnitName);
  // Strukturiert für die volle Anzeige, Klartext für die Kurzform (#654).
  AddDocumentation(Result, Self);
  AddText(Result, 'value', Value);
  if Deprecation <> '' then
  begin
    Result.AddPair('deprecation', StripMarkdown(Deprecation));
  end;
  AddText(Result, 'kind', Kind);
  AddText(Result, 'origin', Origin);
  AddLocation(Result, Self);
  AddText(Result, 'docWiki', DocWikiUrl);
  AddLinks(Result, Links);
  // published-Properties und Ereignisse (#110).
  mMembers := TPublishedMembers.ToJson(PublishedItems, DefaultProperty);
  if mMembers <> nil then
  begin
    Result.AddPair('published', mMembers);
  end;
  AddAncestors(Result, Self);
  AddReassigned(Result, Self);
end;

function THoverInfo.ToMarkdown: string;
begin
  Result := '```pascal' + #10 + Declaration + #10 + '```';
  if Deprecation <> '' then
  begin
    Result := Result + #10#10 + Deprecation;
  end;
  if Value <> '' then
  begin
    Result := Result + #10#10 + 'Wert: `' + Value + '`';
  end;
  if Documentation <> '' then
  begin
    Result := Result + #10#10 + Documentation;
  end;
  if Length(Rationale) > 0 then
  begin
    Result := Result + #10#10 + TLspRationale.ToMarkdown(Rationale);
  end;
  if UnitName <> '' then
  begin
    Result := Result + #10#10 + 'Unit `' + UnitName + '`';
  end;
  if DocWikiUrl <> '' then
  begin
    Result := Result + #10#10 + '[DocWiki](' + DocWikiUrl + ')';
  end;
  if WinApi <> '' then
  begin
    Result := Result + #10#10 + WinApi;
  end;
  if Members <> '' then
  begin
    Result := Result + #10#10 + '---' + #10#10 + Members;
  end;
  if Messages <> '' then
  begin
    Result := Result + #10#10 + '---' + #10#10 + Messages;
  end;
  if FormValues <> '' then
  begin
    Result := Result + #10#10 + '---' + #10#10 + FormValues;
  end;
  if Constructors <> '' then
  begin
    Result := Result + #10#10 + '```pascal' + #10 + Constructors + #10 + '```';
  end;
end;

function THoverInfo.ToPlainText: string;
begin
  Result := Declaration;
  if Deprecation <> '' then
  begin
    Result := Result + #10#10 + StripMarkdown(Deprecation);
  end;
  if Value <> '' then
  begin
    Result := Result + #10#10 + 'Wert: ' + Value;
  end;
  if not Doc.IsEmpty then
  begin
    Result := Result + #10#10 + Doc.ToPlainText;
  end
  else if Documentation <> '' then
  begin
    Result := Result + #10#10 + StripMarkdown(Documentation);
  end;
  if Length(Rationale) > 0 then
  begin
    Result := Result + #10#10 + TLspRationale.ToPlainText(Rationale);
  end;
  if UnitName <> '' then
  begin
    Result := Result + #10#10 + 'Unit ' + UnitName;
  end;
  if DocWikiUrl <> '' then
  begin
    Result := Result + #10#10 + 'DocWiki: ' + DocWikiUrl;
  end;
  if Members <> '' then
  begin
    Result := Result + #10#10 + StripMarkdown(Members);
  end;
  if Messages <> '' then
  begin
    Result := Result + #10#10 + StripMarkdown(Messages);
  end;
end;

end.
