unit Atlas.Common.Dfm.FormInfo;

// In der Formulardatei gesetzte Werte einer Komponente (#126), gemeinsam für
// den Hover über ein Formularfeld und das MCP-Werkzeug get_dfm_info (#48).
// Binärdaten erscheinen als "Bild, n Bytes" bzw. "Binärdaten, n Bytes",
// lange Listen werden nach MaxListLines Zeilen gekürzt. Nur die eigene
// Formulardatei: Werte aus Vorfahr-Formularen kennzeichnet Atlas nicht (#115
// nicht geplant).

interface

uses
  System.SysUtils,
  Atlas.Common.Dfm.Contract;

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
    /// <summary>Markdown mit Properties und Ereignissen von AObject und Link auf den DFM-Eintrag.</summary>
    class function ComponentMarkdown(AObject: TDfmObject; const AFormFile: string): string; static;
    /// <summary>Objekt AName in der Formulardatei, deren Formularklasse AFormClass ist; nil sonst.</summary>
    class function FindComponent(ADocument: TDfmDocument; const AFormClass, AName: string): TDfmObject; static;
  end;

implementation

uses
  System.StrUtils,
  System.Classes,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Dfm.Parser;

function CountHexBytes(const AValue: string): Integer;
var
  Index: Integer;
begin
  Result := 0;
  for Index := 1 to Length(AValue) do
  begin
    if CharInSet(AValue[Index], ['0'..'9', 'A'..'F', 'a'..'f']) then
    begin
      Inc(Result);
    end;
  end;
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
    begin
      Exit(Format('Bild, %d Bytes', [CountHexBytes(Value)]));
    end
    else
    begin
      Exit(Format('Binärdaten, %d Bytes', [CountHexBytes(Value)]));
    end;
  end;
  if StartsStr('(', Value) then
  begin
    // Liste: je Zeile ein Eintrag; nach MaxListLines gekürzt.
    Items := nil;
    for Line in SplitString(Copy(Value, 2, Length(Value) - 2), #10) do
    begin
      if Trim(Line) <> '' then
      begin
        Items := Items + [Trim(Line)];
      end;
    end;
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
      begin
        Result := Result + ' ';
      end;
      Result := Result + Items[Index];
    end;
    Exit(Result + ')');
  end;
  Result := Trim(StringReplace(StringReplace(Value, #13, '', [rfReplaceAll]), #10, ' ', [rfReplaceAll]));
  if Length(Result) > MaxValueLength then
  begin
    Result := Copy(Result, 1, MaxValueLength - 3) + '...';
  end;
end;

procedure AddObject(ALines: TStrings; AObject: TDfmObject; ADepth: Integer);
var
  Indent, Events: string;
  Prop: TDfmProperty;
  Child: TDfmObject;
begin
  Indent := StringOfChar(' ', ADepth * 2);
  if AObject.Kind = TDfmObjectKind.Item then
  begin
    ALines.Add(Indent + '- item');
  end
  else
  begin
    ALines.Add(Format('%s- %s: %s%s', [Indent, IfThen(AObject.Name <> '', AObject.Name, '(ohne Namen)'),
      AObject.TypeName, IfThen(AObject.Kind = TDfmObjectKind.Inherited_, ' (geerbt)', '')]));
  end;
  Events := '';
  for Prop in AObject.Properties do
  begin
    if Prop.IsEvent then
    begin
      Events := Events + IfThen(Events <> '', ', ', '') + Prop.Name + ' → ' + Prop.Value;
    end
    else
    begin
      ALines.Add(Format('%s    %s = %s', [Indent, Prop.Name, TFormInfo.ValueText(Prop)]));
    end;
  end;
  if Events <> '' then
  begin
    ALines.Add(Indent + '    Ereignisse: ' + Events);
  end;
  for Child in AObject.Children do
  begin
    AddObject(ALines, Child, ADepth + 1);
  end;
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
    begin
      Lines.Add('Kein Formular gefunden.');
    end
    else
    begin
      AddObject(Lines, Document.Root, 0);
    end;
    for Error in Document.Errors do
    begin
      Lines.Add(Format('Fehler Zeile %d: %s', [Error.Position.Line + 1, Error.Message]));
    end;
    Result := TrimRight(Lines.Text);
  finally
    Lines.Free;
    Document.Free;
  end;
end;


class function TFormInfo.ComponentMarkdown(AObject: TDfmObject; const AFormFile: string): string;
var
  Prop: TDfmProperty;
begin
  Result := Format('**In %s** ([Zeile %d](%s#L%d))', [ExtractFileName(AFormFile), AObject.Range.StartPos.Line + 1,
    TDocumentUris.FromPath(AFormFile), AObject.Range.StartPos.Line + 1]);
  for Prop in AObject.Properties do
  begin
    if Prop.IsEvent then
    begin
      Result := Result + #10 + Format('- %s → `%s`', [Prop.Name, Prop.Value]);
    end
    else
    begin
      Result := Result + #10 + Format('- %s = `%s`', [Prop.Name, ValueText(Prop)]);
    end;
  end;
end;
function SearchByName(AObject: TDfmObject; const AName: string): TDfmObject;
var
  Child: TDfmObject;
begin
  if SameText(AObject.Name, AName) then
  begin
    Exit(AObject);
  end;
  for Child in AObject.Children do
  begin
    Result := SearchByName(Child, AName);
    if Result <> nil then
    begin
      Exit;
    end;
  end;
  Result := nil;
end;

class function TFormInfo.FindComponent(ADocument: TDfmDocument; const AFormClass, AName: string): TDfmObject;
begin
  Result := nil;
  if (ADocument = nil) or (ADocument.Root = nil) or not SameText(ADocument.Root.TypeName, AFormClass) then
  begin
    Exit;
  end;
  Result := SearchByName(ADocument.Root, AName);
end;

end.
