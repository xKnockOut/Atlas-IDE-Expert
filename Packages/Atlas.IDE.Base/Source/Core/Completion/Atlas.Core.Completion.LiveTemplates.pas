unit Atlas.Core.Completion.LiveTemplates;

// Live Templates der IDE als Code-Vorlagen (#51): liest die *.xml unter
// %APPDATA%\Embarcadero\BDS\<Version>\code_templates (Format seit Delphi 2005,
// gleich in Delphi 12 und 13) und setzt sie in das Format von
// Atlas.Core.Completion.Snippets um.
//
//   <template name="forb">          Kürzel
//     <description>…</description>
//     <point name="ident" editable="true"><text>I</text><hint>…</hint></point>
//     <code language="Delphi" delimiter="|"><![CDATA[for |ident| := …|end|]]></code>
//   </template>
//
// Umsetzung im Code: |name| eines Punkts wird Platzhalter ${n:Vorgabe} (n in
// der Reihenfolge des ersten Auftretens, Wiederholungen verknüpft), ein Punkt
// mit editable="false" bleibt sein Vorgabetext; |end| wird $0, |selected| und
// |*| (Einrückung) entfallen bzw. werden zwei Leerzeichen, || ist das
// Trennzeichen selbst. Ein "$" im Code wird zu "$$". Vorlagen für andere
// Sprachen als Delphi und Vorlagen ohne Code werden übersprungen; Skripte
// (<script>) versteht Atlas nicht, sie entfallen, die Vorlage bleibt.
//
// Kein XML-Parser der RTL: Xml.XMLDoc bräuchte MSXML und COM. Das Format ist
// klein; Elemente, Attribute, Text, CDATA und die fünf Standard-Entitäten
// reichen.

interface

uses
  System.SysUtils,
  Atlas.Core.Completion.Snippets;

type
  TAtlasLiveTemplateStats = record
    /// <summary>Gelesene Vorlagen.</summary>
    Templates: Integer;
    /// <summary>Übersprungene Vorlagen (andere Sprache, kein Code, defekt).</summary>
    Skipped: Integer;
    /// <summary>Entfallene Skripte.</summary>
    Scripts: Integer;
  end;

  TAtlasLiveTemplates = class
  public
    /// <summary>Vorlagen aus einer Datei; AStats zählt mit.</summary>
    class function Parse(const AXml, AFileName: string; var AStats: TAtlasLiveTemplateStats): TAtlasSnippetList; static;
    /// <summary>Alle *.xml unter APath samt Unterordnern.</summary>
    class function LoadFolder(const APath: string; out AStats: TAtlasLiveTemplateStats): TAtlasSnippetList; static;
    /// <summary>Stand des Ordners (Namen und Zeitstempel aller *.xml); '' ohne Ordner.</summary>
    class function FolderStamp(const APath: string): string; static;
    /// <summary>%APPDATA%\Embarcadero\BDS\ABdsVersion\code_templates; '' ohne Version.</summary>
    class function Folder(const ABdsVersion: string): string; static;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.Generics.Collections,
  Atlas.Text.Entities;

type
  /// <summary>Knoten des kleinen XML-Baums.</summary>
  TXmlNode = class
  private
    FChildren: TObjectList<TXmlNode>;
  public
    Name: string;
    Text: string;
    Attributes: TDictionary<string, string>;
    constructor Create(const AName: string);
    destructor Destroy; override;
    function Attribute(const AName: string): string;
    function Child(const AName: string): TXmlNode;
    function ChildText(const AName: string): string;
    property Children: TObjectList<TXmlNode> read FChildren;
  end;

  EXmlError = class(Exception);

constructor TXmlNode.Create(const AName: string);
begin
  inherited Create;
  Name := AName;
  FChildren := TObjectList<TXmlNode>.Create(True);
  Attributes := TDictionary<string, string>.Create;
end;

destructor TXmlNode.Destroy;
begin
  Attributes.Free;
  FChildren.Free;
  inherited;
end;

function TXmlNode.Attribute(const AName: string): string;
begin
  if not Attributes.TryGetValue(LowerCase(AName), Result) then
  begin
    Result := '';
  end;
end;

function TXmlNode.Child(const AName: string): TXmlNode;
var
  Node: TXmlNode;
begin
  for Node in FChildren do
  begin
    if SameText(Node.Name, AName) then
    begin
      Exit(Node);
    end;
  end;
  Result := nil;
end;

function TXmlNode.ChildText(const AName: string): string;
var
  Node: TXmlNode;
begin
  Node := Child(AName);
  if Node = nil then
  begin
    Result := '';
  end
  else
  begin
    Result := Node.Text;
  end;
end;

function IsSpace(AChar: Char): Boolean;
begin
  Result := (AChar = ' ') or (AChar = #9) or (AChar = #10) or (AChar = #13);
end;

/// <summary>Erste Stelle ab APosition in ATag, die kein Leerraum ist.</summary>
function SkipSpaces(const ATag: string; APosition: Integer): Integer;
begin
  Result := APosition;
  while (Result <= Length(ATag)) and IsSpace(ATag[Result]) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Wert hinter "=" ab APosition ("wert" bzw. 'wert'); '' ohne "=" oder ohne Anführungszeichen.
/// APosition steht danach hinter dem Gelesenen.</summary>
function AttributeValue(const ATag: string; var APosition: Integer): string;
var
  mQuote: Char;
  mClose: Integer;
begin
  Result := '';
  if (APosition > Length(ATag)) or (ATag[APosition] <> '=') then
  begin
    Exit;
  end;
  APosition := SkipSpaces(ATag, APosition + 1);
  if (APosition <= Length(ATag)) and ((ATag[APosition] = '"') or (ATag[APosition] = '''')) then
  begin
    mQuote := ATag[APosition];
    mClose := APosition + 1;
    while (mClose <= Length(ATag)) and (ATag[mClose] <> mQuote) do
    begin
      Inc(mClose);
    end;
    Result := TTextEntities.Decode(Copy(ATag, APosition + 1, mClose - APosition - 1));
    APosition := mClose + 1;
  end;
end;

/// <summary>Attribute name="wert" bzw. name='wert' ab APosition in ATag.</summary>
procedure ReadAttributes(ANode: TXmlNode; const ATag: string; APosition: Integer);
var
  mPosition, mClose: Integer;
  mName, mValue: string;
begin
  mPosition := APosition;
  while mPosition <= Length(ATag) do
  begin
    mPosition := SkipSpaces(ATag, mPosition);
    mClose := mPosition;
    while (mClose <= Length(ATag)) and (ATag[mClose] <> '=') and not IsSpace(ATag[mClose]) do
    begin
      Inc(mClose);
    end;
    mName := LowerCase(Copy(ATag, mPosition, mClose - mPosition));
    mPosition := SkipSpaces(ATag, mClose);
    mValue := AttributeValue(ATag, mPosition);
    if mName <> '' then
    begin
      ANode.Attributes.AddOrSetValue(mName, mValue);
    end;
  end;
end;

type
  /// <summary>Liest XML-Text in einen Baum unter einem gegebenen Wurzelknoten.</summary>
  TXmlParser = class
  private
    FXml: string;
    FIndex: Integer;
    FStack: TList<TXmlNode>;
    function Current: TXmlNode;
    /// <summary>Stelle von AMarker ab AFrom; EXmlError mit AError, wenn er fehlt.</summary>
    function EndOf(const AMarker, AError: string; AFrom: Integer): Integer;
    procedure ReadNext;
    procedure ReadText;
    procedure ReadCData;
    procedure SkipComment;
    procedure ReadTag;
    procedure CloseElement(const ATag: string);
    procedure OpenElement(const ATag: string);
  public
    constructor Create(const AXml: string; ARoot: TXmlNode);
    destructor Destroy; override;
    /// <summary>Liest den ganzen Text; EXmlError bei kaputtem Aufbau.</summary>
    procedure Run;
  end;

constructor TXmlParser.Create(const AXml: string; ARoot: TXmlNode);
begin
  inherited Create;
  FXml := AXml;
  FStack := TList<TXmlNode>.Create;
  FStack.Add(ARoot);
end;

destructor TXmlParser.Destroy;
begin
  FStack.Free;
  inherited;
end;

function TXmlParser.Current: TXmlNode;
begin
  Result := FStack[FStack.Count - 1];
end;

function TXmlParser.EndOf(const AMarker, AError: string; AFrom: Integer): Integer;
begin
  Result := Pos(AMarker, FXml, AFrom);
  if Result = 0 then
  begin
    raise EXmlError.Create(AError);
  end;
end;

procedure TXmlParser.Run;
begin
  FIndex := 1;
  while FIndex <= Length(FXml) do
  begin
    ReadNext;
  end;
  if FStack.Count <> 1 then
  begin
    raise EXmlError.Create('Element ohne Ende');
  end;
end;

procedure TXmlParser.ReadNext;
begin
  if FXml[FIndex] <> '<' then
  begin
    ReadText;
  end
  else if Copy(FXml, FIndex, 9) = '<![CDATA[' then
  begin
    ReadCData;
  end
  else if Copy(FXml, FIndex, 4) = '<!--' then
  begin
    SkipComment;
  end
  else
  begin
    ReadTag;
  end;
end;

procedure TXmlParser.ReadText;
var
  mClose: Integer;
begin
  mClose := FIndex;
  while (mClose <= Length(FXml)) and (FXml[mClose] <> '<') do
  begin
    Inc(mClose);
  end;
  Current.Text := Current.Text + TTextEntities.Decode(Copy(FXml, FIndex, mClose - FIndex));
  FIndex := mClose;
end;

procedure TXmlParser.ReadCData;
var
  mClose: Integer;
begin
  mClose := EndOf(']]>', 'CDATA ohne Ende', FIndex + 9);
  Current.Text := Current.Text + Copy(FXml, FIndex + 9, mClose - FIndex - 9);
  FIndex := mClose + 3;
end;

procedure TXmlParser.SkipComment;
begin
  FIndex := EndOf('-->', 'Kommentar ohne Ende', FIndex + 4) + 3;
end;

procedure TXmlParser.ReadTag;
var
  mClose: Integer;
  mTag: string;
begin
  mClose := EndOf('>', 'Tag ohne Ende', FIndex + 1);
  mTag := Copy(FXml, FIndex + 1, mClose - FIndex - 1);
  FIndex := mClose + 1;
  // Verarbeitungsanweisung und DOCTYPE
  if (mTag <> '') and ((mTag[1] = '?') or (mTag[1] = '!')) then
  begin
    Exit;
  end;
  if (mTag <> '') and (mTag[1] = '/') then
  begin
    CloseElement(mTag);
  end
  else
  begin
    OpenElement(mTag);
  end;
end;

procedure TXmlParser.CloseElement(const ATag: string);
begin
  if (FStack.Count <= 1) or not SameText(Trim(Copy(ATag, 2, MaxInt)), Current.Name) then
  begin
    raise EXmlError.Create('Unerwartetes Ende-Tag');
  end;
  FStack.Delete(FStack.Count - 1);
end;

procedure TXmlParser.OpenElement(const ATag: string);
var
  mTag: string;
  mSelfClosing: Boolean;
  mPosition: Integer;
  mNode: TXmlNode;
begin
  mTag := ATag;
  mSelfClosing := (mTag <> '') and (mTag[Length(mTag)] = '/');
  if mSelfClosing then
  begin
    Delete(mTag, Length(mTag), 1);
  end;
  mPosition := 1;
  while (mPosition <= Length(mTag)) and not IsSpace(mTag[mPosition]) do
  begin
    Inc(mPosition);
  end;
  mNode := TXmlNode.Create(Copy(mTag, 1, mPosition - 1));
  Current.Children.Add(mNode);
  ReadAttributes(mNode, mTag, mPosition);
  if not mSelfClosing then
  begin
    FStack.Add(mNode);
  end;
end;

/// <summary>Liest AXml in einen Baum unter einem künstlichen Wurzelknoten; EXmlError bei kaputtem Aufbau.</summary>
function ParseXml(const AXml: string): TXmlNode;
var
  mParser: TXmlParser;
begin
  Result := TXmlNode.Create('');
  try
    mParser := TXmlParser.Create(AXml, Result);
    try
      mParser.Run;
    finally
      mParser.Free;
    end;
  except
    Result.Free;
    raise;
  end;
end;

type
  TTemplatePoint = record
    Default: string;
    Editable: Boolean;
    Number: Integer;
  end;

function Escape(const AText: string): string;
begin
  Result := StringReplace(AText, '$', '$$', [rfReplaceAll]);
end;

/// <summary>Der erste &lt;code&gt;-Knoten für Delphi (ohne Angabe gilt Delphi); zählt die Skripte davor.</summary>
function FindCode(ATemplate: TXmlNode; var AStats: TAtlasLiveTemplateStats): TXmlNode;
var
  mNode: TXmlNode;
begin
  for mNode in ATemplate.Children do
  begin
    if SameText(mNode.Name, 'code') then
    begin
      if (mNode.Attribute('language') = '') or SameText(mNode.Attribute('language'), 'Delphi') then
      begin
        Exit(mNode);
      end;
    end
    else if SameText(mNode.Name, 'script') then
    begin
      Inc(AStats.Scripts);
    end;
  end;
  Result := nil;
end;

function DelimiterOf(ACode: TXmlNode): Char;
begin
  if ACode.Attribute('delimiter') <> '' then
  begin
    Result := ACode.Attribute('delimiter')[1];
  end
  else
  begin
    Result := '|';
  end;
end;

/// <summary>Die &lt;point&gt;-Knoten nach Namen (klein); zählt ihre Skripte.</summary>
procedure CollectPoints(ATemplate: TXmlNode; APoints: TDictionary<string, TTemplatePoint>;
  var AStats: TAtlasLiveTemplateStats);
var
  mNode: TXmlNode;
  mPoint: TTemplatePoint;
begin
  for mNode in ATemplate.Children do
  begin
    if SameText(mNode.Name, 'point') and (mNode.Attribute('name') <> '') then
    begin
      // Die IDE schreibt den Vorgabetext eingerückt auf eigene Zeilen.
      mPoint.Default := Trim(mNode.ChildText('text'));
      mPoint.Editable := not SameText(mNode.Attribute('editable'), 'false');
      mPoint.Number := 0;
      APoints.AddOrSetValue(LowerCase(mNode.Attribute('name')), mPoint);
      if mNode.Child('script') <> nil then
      begin
        Inc(AStats.Scripts);
      end;
    end;
  end;
end;

/// <summary>Platzhalter für den Punkt AName: beim ersten Auftreten mit Vorgabe und neuer Nummer, danach
/// verknüpft; ein nicht bearbeitbarer Punkt bleibt sein Vorgabetext.</summary>
function PointText(const AName: string; APoints: TDictionary<string, TTemplatePoint>; var ANext: Integer): string;
var
  mKey: string;
  mPoint: TTemplatePoint;
begin
  mKey := LowerCase(AName);
  if not APoints.TryGetValue(mKey, mPoint) then
  begin
    // Ohne <point> zeigt die IDE den Namen; Atlas macht ihn zum Platzhalter.
    mPoint.Default := AName;
    mPoint.Editable := True;
    mPoint.Number := 0;
  end;
  if not mPoint.Editable then
  begin
    Exit(Escape(mPoint.Default));
  end;
  if mPoint.Number > 0 then
  begin
    Exit('${' + IntToStr(mPoint.Number) + '}');
  end;
  mPoint.Number := ANext;
  Inc(ANext);
  APoints.AddOrSetValue(mKey, mPoint);
  // "}" beendet den Platzhalter und fällt aus der Vorgabe.
  Result := '${' + IntToStr(mPoint.Number) + ':' +
    StringReplace(StringReplace(mPoint.Default, '}', '', [rfReplaceAll]), #10, ' ', [rfReplaceAll]) + '}';
end;

/// <summary>Umsetzung der Marke |AName|: || ist das Trennzeichen, |end| wird $0, |selected| entfällt, |*| wird
/// zwei Leerzeichen, sonst ein Punkt.</summary>
function MarkerText(const AName: string; ADelimiter: Char; APoints: TDictionary<string, TTemplatePoint>;
  var ANext: Integer): string;
var
  mKey: string;
begin
  mKey := LowerCase(AName);
  if AName = '' then
  begin
    Result := Escape(ADelimiter);
  end
  else if mKey = 'end' then
  begin
    Result := '$0';
  end
  else if mKey = 'selected' then
  begin
    // Atlas setzt Vorlagen ohne Auswahl ein.
    Result := '';
  end
  else if mKey = '*' then
  begin
    Result := '  ';
  end
  else
  begin
    Result := PointText(AName, APoints, ANext);
  end;
end;

/// <summary>Stelle des schließenden Trennzeichens zur Marke ab AIndex in derselben Zeile; 0 ohne.</summary>
function MarkerEnd(const AText: string; AIndex: Integer; ADelimiter: Char): Integer;
begin
  Result := AIndex + 1;
  while (Result <= Length(AText)) and (AText[Result] <> ADelimiter) and (AText[Result] <> #10) do
  begin
    Inc(Result);
  end;
  if (Result > Length(AText)) or (AText[Result] <> ADelimiter) then
  begin
    Result := 0;
  end;
end;

/// <summary>Code mit einheitlichen Zeilenumbrüchen; Leerraum am Anfang und Ende (auch um CDATA) gehört nicht zur
/// Vorlage.</summary>
function NormalizedCode(const AText: string): string;
begin
  Result := Trim(StringReplace(StringReplace(AText, #13#10, #10, [rfReplaceAll]), #13, #10, [rfReplaceAll]));
end;

/// <summary>Setzt den Code AText mit Marken zwischen ADelimiter in das Snippet-Format um.</summary>
function ConvertText(const AText: string; ADelimiter: Char; APoints: TDictionary<string, TTemplatePoint>): string;
var
  mBuilder: TStringBuilder;
  mIndex, mClose, mNext: Integer;
begin
  mBuilder := TStringBuilder.Create;
  try
    mNext := 1;
    mIndex := 1;
    while mIndex <= Length(AText) do
    begin
      mClose := 0;
      if AText[mIndex] = ADelimiter then
      begin
        mClose := MarkerEnd(AText, mIndex, ADelimiter);
      end;
      if mClose = 0 then
      begin
        // Text oder einzelnes Trennzeichen ohne Gegenstück.
        mBuilder.Append(Escape(AText[mIndex]));
        Inc(mIndex);
      end
      else
      begin
        mBuilder.Append(MarkerText(Copy(AText, mIndex + 1, mClose - mIndex - 1), ADelimiter, APoints, mNext));
        mIndex := mClose + 1;
      end;
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

/// <summary>Setzt den Code einer Vorlage in das Snippet-Format um; False ohne verwertbaren Code.</summary>
function ConvertCode(ATemplate: TXmlNode; out ABody: string; var AStats: TAtlasLiveTemplateStats): Boolean;
var
  mCode: TXmlNode;
  mPoints: TDictionary<string, TTemplatePoint>;
begin
  ABody := '';
  mCode := FindCode(ATemplate, AStats);
  if (mCode = nil) or (Trim(mCode.Text) = '') then
  begin
    Exit(False);
  end;
  mPoints := TDictionary<string, TTemplatePoint>.Create;
  try
    CollectPoints(ATemplate, mPoints, AStats);
    ABody := ConvertText(NormalizedCode(mCode.Text), DelimiterOf(mCode), mPoints);
  finally
    mPoints.Free;
  end;
  Result := Trim(ABody) <> '';
end;

{ TAtlasLiveTemplates }

class function TAtlasLiveTemplates.Parse(const AXml, AFileName: string;
  var AStats: TAtlasLiveTemplateStats): TAtlasSnippetList;

  procedure Collect(ANode: TXmlNode);
  var
    Node: TXmlNode;
    Snippet: TAtlasSnippet;
    Body: string;
  begin
    for Node in ANode.Children do
    begin
      if SameText(Node.Name, 'template') then
      begin
        if (Trim(Node.Attribute('name')) <> '') and ConvertCode(Node, Body, AStats) then
        begin
          Snippet := Default(TAtlasSnippet);
          Snippet.Prefix := Trim(Node.Attribute('name'));
          Snippet.Description := Trim(Node.ChildText('description'));
          Snippet.Name := Snippet.Description;
          if Snippet.Name = '' then
          begin
            Snippet.Name := Snippet.Prefix;
          end;
          Snippet.Body := Body;
          Snippet.Origin := TAtlasSnippetOrigin.Ide;
          Snippet.FileName := AFileName;
          Result := Result + [Snippet];
          Inc(AStats.Templates);
        end
        else
        begin
          Inc(AStats.Skipped);
        end;
      end
      else
      begin
        Collect(Node);
      end;
    end;
  end;

var
  Root: TXmlNode;
begin
  Result := nil;
  try
    Root := ParseXml(AXml);
  except
    on EXmlError do
    begin
      Inc(AStats.Skipped);
      Exit;
    end;
  end;
  try
    Collect(Root);
  finally
    Root.Free;
  end;
end;

class function TAtlasLiveTemplates.LoadFolder(const APath: string;
  out AStats: TAtlasLiveTemplateStats): TAtlasSnippetList;
var
  FileName: string;
  Text: string;
begin
  Result := nil;
  AStats := Default(TAtlasLiveTemplateStats);
  if (APath = '') or not TDirectory.Exists(APath) then
  begin
    Exit;
  end;
  for FileName in TDirectory.GetFiles(APath, '*.xml', TSearchOption.soAllDirectories) do
  begin
    try
      Text := TFile.ReadAllText(FileName, TEncoding.UTF8);
    except
      on EInOutError do
      begin
        Inc(AStats.Skipped);
        Continue;
      end;
      on EStreamError do
      begin
        Inc(AStats.Skipped);
        Continue;
      end;
      on EEncodingError do
      begin
        Inc(AStats.Skipped);
        Continue;
      end;
    end;
    Result := Result + Parse(Text, FileName, AStats);
  end;
end;

class function TAtlasLiveTemplates.FolderStamp(const APath: string): string;
var
  FileName: string;
  Age: TDateTime;
begin
  Result := '';
  if (APath = '') or not TDirectory.Exists(APath) then
  begin
    Exit;
  end;
  Result := '+';
  for FileName in TDirectory.GetFiles(APath, '*.xml', TSearchOption.soAllDirectories) do
  begin
    if not FileAge(FileName, Age) then
    begin
      Age := 0;
    end;
    Result := Result + FileName + '|' + FloatToStr(Age, TFormatSettings.Invariant) + ';';
  end;
end;

class function TAtlasLiveTemplates.Folder(const ABdsVersion: string): string;
begin
  Result := GetEnvironmentVariable('APPDATA');
  if (Result = '') or (ABdsVersion = '') then
  begin
    Exit('');
  end;
  Result := IncludeTrailingPathDelimiter(Result) + 'Embarcadero\BDS\' + ABdsVersion + '\code_templates';
end;

end.
