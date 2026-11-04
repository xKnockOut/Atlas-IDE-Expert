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

/// <summary>Liest AXml in einen Baum unter einem künstlichen Wurzelknoten; EXmlError bei kaputtem Aufbau.</summary>
function ParseXml(const AXml: string): TXmlNode;
var
  Index: Integer;
  Stack: TList<TXmlNode>;
  Node: TXmlNode;
  Close: Integer;
  Tag, Name, Value: string;
  Quote: Char;
  SelfClosing: Boolean;
  Position: Integer;

  function Current: TXmlNode;
  begin
    Result := Stack[Stack.Count - 1];
  end;

  function IsSpace(C: Char): Boolean;
  begin
    Result := (C = ' ') or (C = #9) or (C = #10) or (C = #13);
  end;

begin
  Result := TXmlNode.Create('');
  Stack := TList<TXmlNode>.Create;
  try
    try
      Stack.Add(Result);
      Index := 1;
      while Index <= Length(AXml) do
      begin
        if AXml[Index] <> '<' then
        begin
          Close := Index;
          while (Close <= Length(AXml)) and (AXml[Close] <> '<') do
          begin
            Inc(Close);
          end;
          Current.Text := Current.Text + TTextEntities.Decode(Copy(AXml, Index, Close - Index));
          Index := Close;
          Continue;
        end;
        if Copy(AXml, Index, 9) = '<![CDATA[' then
        begin
          Close := Pos(']]>', AXml, Index + 9);
          if Close = 0 then
          begin
            raise EXmlError.Create('CDATA ohne Ende');
          end;
          Current.Text := Current.Text + Copy(AXml, Index + 9, Close - Index - 9);
          Index := Close + 3;
          Continue;
        end;
        if Copy(AXml, Index, 4) = '<!--' then
        begin
          Close := Pos('-->', AXml, Index + 4);
          if Close = 0 then
          begin
            raise EXmlError.Create('Kommentar ohne Ende');
          end;
          Index := Close + 3;
          Continue;
        end;
        Close := Pos('>', AXml, Index + 1);
        if Close = 0 then
        begin
          raise EXmlError.Create('Tag ohne Ende');
        end;
        Tag := Copy(AXml, Index + 1, Close - Index - 1);
        Index := Close + 1;
        // Verarbeitungsanweisung und DOCTYPE
        if (Tag <> '') and ((Tag[1] = '?') or (Tag[1] = '!')) then
        begin
          Continue;
        end;
        if (Tag <> '') and (Tag[1] = '/') then
        begin
          if (Stack.Count <= 1) or not SameText(Trim(Copy(Tag, 2, MaxInt)), Current.Name) then
          begin
            raise EXmlError.Create('Unerwartetes Ende-Tag');
          end;
          Stack.Delete(Stack.Count - 1);
          Continue;
        end;
        SelfClosing := (Tag <> '') and (Tag[Length(Tag)] = '/');
        if SelfClosing then
        begin
          Delete(Tag, Length(Tag), 1);
        end;
        Position := 1;
        while (Position <= Length(Tag)) and not IsSpace(Tag[Position]) do
        begin
          Inc(Position);
        end;
        Node := TXmlNode.Create(Copy(Tag, 1, Position - 1));
        Current.Children.Add(Node);
        // Attribute: name="wert" bzw. name='wert'
        while Position <= Length(Tag) do
        begin
          while (Position <= Length(Tag)) and IsSpace(Tag[Position]) do
          begin
            Inc(Position);
          end;
          Close := Position;
          while (Close <= Length(Tag)) and (Tag[Close] <> '=') and not IsSpace(Tag[Close]) do
          begin
            Inc(Close);
          end;
          Name := LowerCase(Copy(Tag, Position, Close - Position));
          Position := Close;
          while (Position <= Length(Tag)) and IsSpace(Tag[Position]) do
          begin
            Inc(Position);
          end;
          Value := '';
          if (Position <= Length(Tag)) and (Tag[Position] = '=') then
          begin
            Inc(Position);
            while (Position <= Length(Tag)) and IsSpace(Tag[Position]) do
            begin
              Inc(Position);
            end;
            if (Position <= Length(Tag)) and ((Tag[Position] = '"') or (Tag[Position] = '''')) then
            begin
              Quote := Tag[Position];
              Close := Position + 1;
              while (Close <= Length(Tag)) and (Tag[Close] <> Quote) do
              begin
                Inc(Close);
              end;
              Value := TTextEntities.Decode(Copy(Tag, Position + 1, Close - Position - 1));
              Position := Close + 1;
            end;
          end;
          if Name <> '' then
          begin
            Node.Attributes.AddOrSetValue(Name, Value);
          end;
        end;
        if not SelfClosing then
        begin
          Stack.Add(Node);
        end;
      end;
      if Stack.Count <> 1 then
      begin
        raise EXmlError.Create('Element ohne Ende');
      end;
    except
      Result.Free;
      raise;
    end;
  finally
    Stack.Free;
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

/// <summary>Setzt den Code einer Vorlage in das Snippet-Format um; False ohne verwertbaren Code.</summary>
function ConvertCode(ATemplate: TXmlNode; out ABody: string; var AStats: TAtlasLiveTemplateStats): Boolean;
var
  Points: TDictionary<string, TTemplatePoint>;
  Point: TTemplatePoint;
  Node, Code: TXmlNode;
  Delimiter: Char;
  Text, Name, Key: string;
  Index, Close, Next: Integer;
  Builder: TStringBuilder;
begin
  Result := False;
  ABody := '';
  Code := nil;
  for Node in ATemplate.Children do
  begin
    if SameText(Node.Name, 'code') then
    begin
      // Nur Delphi; ohne Angabe gilt Delphi.
      if (Node.Attribute('language') = '') or SameText(Node.Attribute('language'), 'Delphi') then
      begin
        Code := Node;
        Break;
      end;
    end
    else if SameText(Node.Name, 'script') then
    begin
      Inc(AStats.Scripts);
    end;
  end;
  if (Code = nil) or (Trim(Code.Text) = '') then
  begin
    Exit;
  end;
  Text := Code.Text;
  if Code.Attribute('delimiter') <> '' then
  begin
    Delimiter := Code.Attribute('delimiter')[1];
  end
  else
  begin
    Delimiter := '|';
  end;
  Points := TDictionary<string, TTemplatePoint>.Create;
  Builder := TStringBuilder.Create;
  try
    for Node in ATemplate.Children do
    begin
      if SameText(Node.Name, 'point') and (Node.Attribute('name') <> '') then
      begin
        // Die IDE schreibt den Vorgabetext eingerückt auf eigene Zeilen.
        Point.Default := Trim(Node.ChildText('text'));
        Point.Editable := not SameText(Node.Attribute('editable'), 'false');
        Point.Number := 0;
        Points.AddOrSetValue(LowerCase(Node.Attribute('name')), Point);
        if Node.Child('script') <> nil then
        begin
          Inc(AStats.Scripts);
        end;
      end;
    end;
    Next := 1;
    // Zeilenumbrüche vereinheitlichen; Leerraum am Anfang und Ende (auch um CDATA) gehört nicht zur Vorlage.
    Text := StringReplace(StringReplace(Text, #13#10, #10, [rfReplaceAll]), #13, #10, [rfReplaceAll]);
    Text := Trim(Text);
    Index := 1;
    while Index <= Length(Text) do
    begin
      if Text[Index] <> Delimiter then
      begin
        Builder.Append(Escape(Text[Index]));
        Inc(Index);
        Continue;
      end;
      Close := Index + 1;
      while (Close <= Length(Text)) and (Text[Close] <> Delimiter) and (Text[Close] <> #10) do
      begin
        Inc(Close);
      end;
      if (Close > Length(Text)) or (Text[Close] <> Delimiter) then
      begin
        // Einzelnes Trennzeichen ohne Gegenstück: als Text übernehmen.
        Builder.Append(Escape(Text[Index]));
        Inc(Index);
        Continue;
      end;
      Name := Copy(Text, Index + 1, Close - Index - 1);
      Key := LowerCase(Name);
      Index := Close + 1;
      if Name = '' then
      begin
        Builder.Append(Escape(Delimiter));
      end
      else if Key = 'end' then
      begin
        Builder.Append('$0');
      end
      else if Key = 'selected' then
        // Atlas setzt Vorlagen ohne Auswahl ein.
      else if Key = '*' then
      begin
        Builder.Append('  ');
      end
      else
      begin
        if not Points.TryGetValue(Key, Point) then
        begin
          // Ohne <point> zeigt die IDE den Namen; Atlas macht ihn zum Platzhalter.
          Point.Default := Name;
          Point.Editable := True;
          Point.Number := 0;
        end;
        if not Point.Editable then
        begin
          Builder.Append(Escape(Point.Default));
        end
        else if Point.Number > 0 then
        begin
          Builder.Append('${' + IntToStr(Point.Number) + '}');
        end
        else
        begin
          Point.Number := Next;
          Inc(Next);
          Points.AddOrSetValue(Key, Point);
          // "}" beendet den Platzhalter und fällt aus der Vorgabe.
          Builder.Append('${' + IntToStr(Point.Number) + ':' +
            StringReplace(StringReplace(Point.Default, '}', '', [rfReplaceAll]), #10, ' ', [rfReplaceAll]) + '}');
        end;
      end;
    end;
    ABody := Builder.ToString;
    Result := Trim(ABody) <> '';
  finally
    Builder.Free;
    Points.Free;
  end;
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
