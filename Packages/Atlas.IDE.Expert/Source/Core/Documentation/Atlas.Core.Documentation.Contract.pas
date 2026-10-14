unit Atlas.Core.Documentation.Contract;

// Strukturierte XMLDoc (#654) aus "atlas.documentation" der Hover-Antwort bzw.
// "data.atlas.documentation" der Resolve-Antwort: Abschnitte (summary, param,
// typeparam, returns, value, exception, remarks, example, seealso) mit Läufen
// (Text, Code, Verweis mit Fundort, Link, Absatz, Codeblock, Listenpunkt,
// Tabellenzelle). Dazu die Anzeige-Einstellungen "xmlDoc" (voll bzw. Kurzform,
// Zeilengrenze), die der Server je Projekt meldet.

interface

uses
  System.JSON;

{$SCOPEDENUMS ON}

type
  /// <summary>Art eines Laufs; Namen wie im Server (text, code, ref, link, paramref, keyword, br, para,
  /// codeblock, bullet, cell).</summary>
  TAtlasDocRunKind = (Text, Code, Ref, Link, ParamRef, Keyword, LineBreak, Paragraph, CodeBlock, Bullet, Cell);

  TAtlasDocSectionKind = (Summary, Param, TypeParam, Returns, Value, Exception, Remarks, Example, SeeAlso);

  /// <summary>Ziel eines Verweises; FileName '' ohne Fundort (Name, Unit bleiben).</summary>
  TAtlasDocTarget = record
    Name: string;
    UnitName: string;
    FileName: string;
    /// <summary>0-basiert.</summary>
    Line: Integer;
    Character: Integer;
    function HasLocation: Boolean;
    class function FromJson(const AObject: TJSONObject): TAtlasDocTarget; static;
  end;

  TAtlasDocRun = record
    Kind: TAtlasDocRunKind;
    Text: string;
    /// <summary>Ref: cref (ohne Präfix); Link: URL.</summary>
    Target: string;
    Bold: Boolean;
    Italic: Boolean;
    /// <summary>Bullet: Listenebene ab 1.</summary>
    Level: Integer;
    /// <summary>Ref: Fundort, wenn der Server ihn kennt.</summary>
    Location: TAtlasDocTarget;
    class function Create(AKind: TAtlasDocRunKind; const AText: string;
      const ATarget: string = ''): TAtlasDocRun; static;
  end;

  TAtlasDocRuns = TArray<TAtlasDocRun>;

  TAtlasDocSection = record
    Kind: TAtlasDocSectionKind;
    /// <summary>Param, TypeParam: Name; Exception: Klasse.</summary>
    Name: string;
    /// <summary>Exception: Fundort der Klasse, wenn bekannt.</summary>
    NameRef: TAtlasDocTarget;
    Runs: TAtlasDocRuns;
    /// <summary>Text der Läufe ohne Auszeichnung (für Sprachausgabe und Tests).</summary>
    function Text: string;
  end;

  TAtlasDoc = record
    Sections: TArray<TAtlasDocSection>;
    function IsEmpty: Boolean;
    function Has(AKind: TAtlasDocSectionKind): Boolean;
    /// <summary>Objekt mit "sections"; nil bzw. anderes ergibt eine leere Doku.</summary>
    class function FromJson(const AValue: TJSONValue): TAtlasDoc; static;
    /// <summary>Klartext fremder Server als eine Beschreibung: Zeilenumbrüche bleiben, Leerzeilen trennen
    /// Absätze, eingerückte Zeilen behalten ihre Einrückung.</summary>
    class function FromText(const AText: string): TAtlasDoc; static;
    class function TryParseRunKind(const AName: string; out AKind: TAtlasDocRunKind): Boolean; static;
    class function TryParseSectionKind(const AName: string; out AKind: TAtlasDocSectionKind): Boolean; static;
  end;

  /// <summary>Anzeige der XMLDoc (#654): volle Doku bzw. Kurzform (Beschreibung vier, Bemerkungen drei
  /// Zeilen) und höchstens MaxLines Zeilen ohne Scrollen (0 = bis zur Bildschirmhöhe).</summary>
  TAtlasDocDisplay = record
  public const
    MaxMaxLines = 50;
    ShortSummaryLines = 4;
    ShortRemarksLines = 3;
  public
    /// <summary>Vom Server gemeldet (atlas.json bzw. Einstellungen des Plugins).</summary>
    Known: Boolean;
    Full: Boolean;
    MaxLines: Integer;
    class function Create(AFull: Boolean; AMaxLines: Integer): TAtlasDocDisplay; static;
    /// <summary>"xmlDoc" der Antwort; ohne Angabe AFallback (Einstellungen des Plugins).</summary>
    class function FromJson(const AValue: TJSONValue; const AFallback: TAtlasDocDisplay): TAtlasDocDisplay; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math;

const
  RunKindNames: array[TAtlasDocRunKind] of string = ('text', 'code', 'ref', 'link', 'paramref', 'keyword', 'br',
    'para', 'codeblock', 'bullet', 'cell');
  SectionKindNames: array[TAtlasDocSectionKind] of string = ('summary', 'param', 'typeparam', 'returns', 'value',
    'exception', 'remarks', 'example', 'seealso');

{ TAtlasDocTarget }

function TAtlasDocTarget.HasLocation: Boolean;
begin
  Result := FileName <> '';
end;

class function TAtlasDocTarget.FromJson(const AObject: TJSONObject): TAtlasDocTarget;
begin
  Result := Default(TAtlasDocTarget);
  if AObject = nil then
    Exit;
  Result.Name := AObject.GetValue<string>('name', '');
  Result.UnitName := AObject.GetValue<string>('unit', '');
  Result.FileName := AObject.GetValue<string>('file', '');
  Result.Line := AObject.GetValue<Integer>('line', 0);
  Result.Character := AObject.GetValue<Integer>('character', 0);
end;

{ TAtlasDocRun }

class function TAtlasDocRun.Create(AKind: TAtlasDocRunKind; const AText, ATarget: string): TAtlasDocRun;
begin
  Result := Default(TAtlasDocRun);
  Result.Kind := AKind;
  Result.Text := AText;
  Result.Target := ATarget;
end;

{ TAtlasDocSection }

function TAtlasDocSection.Text: string;
var
  Run: TAtlasDocRun;
begin
  Result := '';
  for Run in Runs do
    case Run.Kind of
      TAtlasDocRunKind.LineBreak, TAtlasDocRunKind.Paragraph:
        Result := Result + #10;
      TAtlasDocRunKind.CodeBlock:
        Result := Result + #10 + Run.Text + #10;
      TAtlasDocRunKind.Bullet:
        if Run.Text = '' then
          Result := Result + #10
        else
          Result := Result + #10 + Run.Text + ' ';
      TAtlasDocRunKind.Cell:
        Result := Result + ' – ';
    else
      Result := Result + Run.Text;
    end;
  Result := Trim(Result);
end;

{ TAtlasDoc }

function TAtlasDoc.IsEmpty: Boolean;
begin
  Result := Length(Sections) = 0;
end;

function TAtlasDoc.Has(AKind: TAtlasDocSectionKind): Boolean;
var
  Section: TAtlasDocSection;
begin
  for Section in Sections do
    if Section.Kind = AKind then
      Exit(True);
  Result := False;
end;

class function TAtlasDoc.TryParseRunKind(const AName: string; out AKind: TAtlasDocRunKind): Boolean;
var
  Kind: TAtlasDocRunKind;
begin
  for Kind := Low(TAtlasDocRunKind) to High(TAtlasDocRunKind) do
    if SameText(RunKindNames[Kind], AName) then
    begin
      AKind := Kind;
      Exit(True);
    end;
  Result := False;
end;

class function TAtlasDoc.TryParseSectionKind(const AName: string; out AKind: TAtlasDocSectionKind): Boolean;
var
  Kind: TAtlasDocSectionKind;
begin
  for Kind := Low(TAtlasDocSectionKind) to High(TAtlasDocSectionKind) do
    if SameText(SectionKindNames[Kind], AName) then
    begin
      AKind := Kind;
      Exit(True);
    end;
  Result := False;
end;

class function TAtlasDoc.FromJson(const AValue: TJSONValue): TAtlasDoc;
var
  List, Runs: TJSONArray;
  Item, RunItem: TJSONValue;
  Ref: TJSONValue;
  Section: TAtlasDocSection;
  Run: TAtlasDocRun;
  SectionKind: TAtlasDocSectionKind;
  RunKind: TAtlasDocRunKind;
begin
  Result := Default(TAtlasDoc);
  if not (AValue is TJSONObject) then
    Exit;
  List := nil;
  if not TJSONObject(AValue).TryGetValue<TJSONArray>('sections', List) then
    Exit;
  for Item in List do
  begin
    // Unbekannte Abschnitte und Läufe (neuerer Server) überspringen statt abbrechen.
    if not (Item is TJSONObject) or
      not TryParseSectionKind(TJSONObject(Item).GetValue<string>('kind', ''), SectionKind) then
      Continue;
    Section := Default(TAtlasDocSection);
    Section.Kind := SectionKind;
    Section.Name := TJSONObject(Item).GetValue<string>('name', '');
    Ref := TJSONObject(Item).GetValue('ref');
    if Ref is TJSONObject then
    begin
      Section.NameRef := TAtlasDocTarget.FromJson(TJSONObject(Ref));
      if Section.NameRef.Name = '' then
        Section.NameRef.Name := Section.Name;
    end;
    Runs := nil;
    if TJSONObject(Item).TryGetValue<TJSONArray>('runs', Runs) then
      for RunItem in Runs do
      begin
        if not (RunItem is TJSONObject) or
          not TryParseRunKind(TJSONObject(RunItem).GetValue<string>('kind', ''), RunKind) then
          Continue;
        Run := TAtlasDocRun.Create(RunKind, TJSONObject(RunItem).GetValue<string>('text', ''),
          TJSONObject(RunItem).GetValue<string>('target', ''));
        Run.Bold := TJSONObject(RunItem).GetValue<Boolean>('bold', False);
        Run.Italic := TJSONObject(RunItem).GetValue<Boolean>('italic', False);
        Run.Level := TJSONObject(RunItem).GetValue<Integer>('level', 0);
        if RunKind = TAtlasDocRunKind.Ref then
        begin
          Run.Location := TAtlasDocTarget.FromJson(TJSONObject(RunItem));
          if Run.Location.Name = '' then
            Run.Location.Name := Run.Target;
        end;
        Section.Runs := Section.Runs + [Run];
      end;
    Result.Sections := Result.Sections + [Section];
  end;
end;

class function TAtlasDoc.FromText(const AText: string): TAtlasDoc;
var
  Section: TAtlasDocSection;
  Line: string;
  Pending: TAtlasDocRunKind;
  HasPending: Boolean;
  Last: Integer;
begin
  Result := Default(TAtlasDoc);
  if Trim(AText) = '' then
    Exit;
  Section := Default(TAtlasDocSection);
  Section.Kind := TAtlasDocSectionKind.Summary;
  HasPending := False;
  Pending := TAtlasDocRunKind.LineBreak;
  for Line in Trim(StringReplace(AText, #13#10, #10, [rfReplaceAll])).Split([#10]) do
  begin
    if Trim(Line) = '' then
    begin
      Pending := TAtlasDocRunKind.Paragraph;
      HasPending := Length(Section.Runs) > 0;
      Continue;
    end;
    Last := High(Section.Runs);
    // Eingerückte Zeilen (Code, Beispiele) als Codeblock mit Einrückung; aufeinanderfolgende in einem.
    if Line.StartsWith(' ') and (Last >= 0) and (Section.Runs[Last].Kind = TAtlasDocRunKind.CodeBlock) and
      (Pending = TAtlasDocRunKind.LineBreak) then
    begin
      Section.Runs[Last].Text := Section.Runs[Last].Text + #10 + TrimRight(Line);
      Continue;
    end;
    if HasPending then
      Section.Runs := Section.Runs + [TAtlasDocRun.Create(Pending, '')];
    if Line.StartsWith(' ') then
      Section.Runs := Section.Runs + [TAtlasDocRun.Create(TAtlasDocRunKind.CodeBlock, TrimRight(Line))]
    else
      Section.Runs := Section.Runs + [TAtlasDocRun.Create(TAtlasDocRunKind.Text, TrimRight(Line))];
    HasPending := True;
    Pending := TAtlasDocRunKind.LineBreak;
  end;
  Result.Sections := [Section];
end;

{ TAtlasDocDisplay }

class function TAtlasDocDisplay.Create(AFull: Boolean; AMaxLines: Integer): TAtlasDocDisplay;
begin
  Result.Known := False;
  Result.Full := AFull;
  Result.MaxLines := EnsureRange(AMaxLines, 0, MaxMaxLines);
end;

class function TAtlasDocDisplay.FromJson(const AValue: TJSONValue;
  const AFallback: TAtlasDocDisplay): TAtlasDocDisplay;
begin
  Result := AFallback;
  if not (AValue is TJSONObject) then
    Exit;
  Result.Known := True;
  Result.Full := TJSONObject(AValue).GetValue<Boolean>('full', AFallback.Full);
  Result.MaxLines := EnsureRange(TJSONObject(AValue).GetValue<Integer>('maxLines', AFallback.MaxLines), 0,
    MaxMaxLines);
end;

end.
