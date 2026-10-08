unit BDLsp.Common.Dfm.FormInfo;

// In der Formulardatei gesetzte Werte einer Komponente (#126), gemeinsam für
// den Hover über ein Formularfeld und das MCP-Werkzeug get_dfm_info (#48).
// Binärdaten erscheinen als "Bild, n Bytes" bzw. "Binärdaten, n Bytes",
// lange Listen werden nach MaxListLines Zeilen gekürzt. Werte aus dem
// Vorfahr-Formular (#115) sind als geerbt gekennzeichnet.

interface

uses
  System.SysUtils,
  BDLsp.Common.Dfm.Contract,
  BDLsp.Common.Dfm.FormInheritance;

type
  TFormInfo = class
  public const
    MaxValueLength = 60;
    MaxListLines = 10;
  public
    /// <summary>Wert einer Property für die Anzeige, einzeilig außer bei gekürzten Listen.</summary>
    class function ValueText(const AProperty: TDfmProperty): string; static;
    /// <summary>Komponentenbaum als Text wie in get_dfm_info.</summary>
    class function Describe(const AFormText: string): string; static;
    /// <summary>Markdown mit Properties und Ereignissen von AObject und Link auf den DFM-Eintrag.
    /// AChain darf nil sein; sonst kommen geerbte Werte gekennzeichnet dazu.</summary>
    class function ComponentMarkdown(AObject: TDfmObject; const AFormFile: string;
      AChain: TFormInheritance = nil): string; static;
    /// <summary>Objekt AName in der Formulardatei, deren Formularklasse AFormClass ist; nil sonst.</summary>
    class function FindComponent(ADocument: TDfmDocument; const AFormClass, AName: string): TDfmObject; static;
  end;

implementation

uses
  System.StrUtils,
  System.Classes,
  BDLsp.Common.Documents.Uris,
  BDLsp.Common.Dfm.Parser;

function CountHexBytes(const AValue: string): Integer;
var
  Index: Integer;
begin
  Result := 0;
  for Index := 1 to Length(AValue) do
    if CharInSet(AValue[Index], ['0'..'9', 'A'..'F', 'a'..'f']) then
      Inc(Result);
  Result := Result div 2;
end;

function IsPicture(const AName: string): Boolean;
begin
  Result := EndsText('Picture.Data', AName) or EndsText('Glyph.Data', AName) or EndsText('Bitmap.Data', AName) or
    EndsText('Icon.Data', AName);
end;

class function TFormInfo.ValueText(const AProperty: TDfmProperty): string;
var
  Value, Line: string;
  Items: TArray<string>;
  Index, Count: Integer;
begin
  Value := Trim(AProperty.Value);
  if StartsStr('{', Value) then
  begin
    if IsPicture(AProperty.Name) then
      Exit(Format('Bild, %d Bytes', [CountHexBytes(Value)]))
    else
      Exit(Format('Binärdaten, %d Bytes', [CountHexBytes(Value)]));
  end;
  if StartsStr('(', Value) then
  begin
    // Liste: je Zeile ein Eintrag; nach MaxListLines gekürzt.
    Items := nil;
    for Line in SplitString(Copy(Value, 2, Length(Value) - 2), #10) do
      if Trim(Line) <> '' then
        Items := Items + [Trim(Line)];
    Result := '(';
    Count := Length(Items);
    for Index := 0 to Count - 1 do
    begin
      if Index = MaxListLines then
      begin
        Result := Result + Format(' … %d weitere', [Count - MaxListLines]);
        Break;
      end;
      if Index > 0 then
        Result := Result + ' ';
      Result := Result + Items[Index];
    end;
    Exit(Result + ')');
  end;
  Result := Trim(StringReplace(StringReplace(Value, #13, '', [rfReplaceAll]), #10, ' ', [rfReplaceAll]));
  if Length(Result) > MaxValueLength then
    Result := Copy(Result, 1, MaxValueLength - 3) + '...';
end;

procedure AddObject(ALines: TStrings; AObject: TDfmObject; ADepth: Integer);
var
  Indent, Events: string;
  Prop: TDfmProperty;
  Child: TDfmObject;
begin
  Indent := StringOfChar(' ', ADepth * 2);
  if AObject.Kind = TDfmObjectKind.Item then
    ALines.Add(Indent + '- item')
  else
    ALines.Add(Format('%s- %s: %s%s', [Indent, IfThen(AObject.Name <> '', AObject.Name, '(ohne Namen)'),
      AObject.TypeName, IfThen(AObject.Kind = TDfmObjectKind.Inherited_, ' (geerbt)', '')]));
  Events := '';
  for Prop in AObject.Properties do
    if Prop.IsEvent then
      Events := Events + IfThen(Events <> '', ', ', '') + Prop.Name + ' → ' + Prop.Value
    else
      ALines.Add(Format('%s    %s = %s', [Indent, Prop.Name, TFormInfo.ValueText(Prop)]));
  if Events <> '' then
    ALines.Add(Indent + '    Ereignisse: ' + Events);
  for Child in AObject.Children do
    AddObject(ALines, Child, ADepth + 1);
end;

class function TFormInfo.Describe(const AFormText: string): string;
var
  Document: TDfmDocument;
  Lines: TStringList;
  Error: TDfmError;
begin
  Document := TDfmParser.Parse(AFormText);
  Lines := TStringList.Create;
  try
    if Document.Root = nil then
      Lines.Add('Kein Formular gefunden.')
    else
      AddObject(Lines, Document.Root, 0);
    for Error in Document.Errors do
      Lines.Add(Format('Fehler Zeile %d: %s', [Error.Position.Line + 1, Error.Message]));
    Result := TrimRight(Lines.Text);
  finally
    Lines.Free;
    Document.Free;
  end;
end;

function SetLocally(AObject: TDfmObject; const AName: string): Boolean;
var
  Prop: TDfmProperty;
begin
  for Prop in AObject.Properties do
    if SameText(Prop.Name, AName) then
      Exit(True);
  Result := False;
end;

class function TFormInfo.ComponentMarkdown(AObject: TDfmObject; const AFormFile: string;
  AChain: TFormInheritance): string;
var
  Prop: TDfmProperty;
  Levels: TArray<TFormLevel>;
  Level: Integer;
  Ancestor: TDfmObject;
  Seen, Line: string;
begin
  Result := Format('**In %s** ([Zeile %d](%s#L%d))', [ExtractFileName(AFormFile), AObject.Range.StartPos.Line + 1,
    TDocumentUris.FromPath(AFormFile), AObject.Range.StartPos.Line + 1]);
  for Prop in AObject.Properties do
    if Prop.IsEvent then
      Result := Result + #10 + Format('- %s → `%s`', [Prop.Name, Prop.Value])
    else
      Result := Result + #10 + Format('- %s = `%s`', [Prop.Name, ValueText(Prop)]);
  if AChain = nil then
    Exit;
  // Werte aus den Vorfahr-Formularen, die hier nicht überschrieben sind.
  Seen := ';';
  Levels := AChain.Levels;
  for Level := 1 to High(Levels) do
  begin
    if Levels[Level].Document.Root = nil then
      Continue;
    Ancestor := FindComponent(Levels[Level].Document, Levels[Level].FormClass, AObject.Name);
    if Ancestor = nil then
      Continue;
    for Prop in Ancestor.Properties do
      if not SetLocally(AObject, Prop.Name) and (Pos(';' + LowerCase(Prop.Name) + ';', Seen) = 0) then
      begin
        Seen := Seen + LowerCase(Prop.Name) + ';';
        if Prop.IsEvent then
          Line := Format('- %s → `%s`', [Prop.Name, Prop.Value])
        else
          Line := Format('- %s = `%s`', [Prop.Name, ValueText(Prop)]);
        Result := Result + #10 + Line + ' (geerbt aus ' + Levels[Level].FormClass + ')';
      end;
  end;
end;

function SearchByName(AObject: TDfmObject; const AName: string): TDfmObject;
var
  Child: TDfmObject;
begin
  if SameText(AObject.Name, AName) then
    Exit(AObject);
  for Child in AObject.Children do
  begin
    Result := SearchByName(Child, AName);
    if Result <> nil then
      Exit;
  end;
  Result := nil;
end;

class function TFormInfo.FindComponent(ADocument: TDfmDocument; const AFormClass, AName: string): TDfmObject;
begin
  Result := nil;
  if (ADocument = nil) or (ADocument.Root = nil) or not SameText(ADocument.Root.TypeName, AFormClass) then
    Exit;
  Result := SearchByName(ADocument.Root, AName);
end;

end.
