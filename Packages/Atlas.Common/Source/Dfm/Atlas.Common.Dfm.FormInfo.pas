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
    cMaxValueLength = 60;
    cMaxListLines = 10;
  public
    /// <summary>Wert einer Property für die Anzeige, einzeilig außer bei gekürzten Listen.</summary>
    class function ValueText(const AProperty: TDfmProperty): string; static;
    /// <summary>Komponentenbaum als Text wie in get_dfm_info.</summary>
    class function Describe(const AFormText: string): string; static;
    /// <summary>Markdown mit Properties und Ereignissen von AObject und Link auf den DFM-Eintrag.</summary>
    class function ComponentMarkdown(AObject: TDfmObject; const AFormFile: string): string; static;
    /// <summary>Objekt AName in der Formulardatei, deren Formularklasse AFormClass ist; nil sonst.</summary>
    class function FindComponent(ADocument: TDfmDocument; const AFormClass, AName: string): TDfmObject; static;
    /// <summary>ComponentMarkdown des Felds AFieldName im Formular AFormText mit der Formularklasse AFormClass
    /// (#126); '' ohne Formulartext oder Komponente.</summary>
    class function FieldMarkdown(const AFormText, AFormFile, AFormClass, AFieldName: string): string; static;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  System.Classes,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Dfm.Parser,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TFormInfoText = (BinaryDataBytes, NoFormFound, ErrorLine, WithoutName, InLineL, More, ImageBytes, InheritedText,
    Events);

const
  cTexts: array[TFormInfoText] of TAtlasText = (
    (De: 'Binärdaten, %d Bytes'; En: 'Binary data, %d bytes'),
    (De: 'Kein Formular gefunden.'; En: 'No form found.'),
    (De: 'Fehler Zeile %d: %s'; En: 'Error line %d: %s'),
    (De: '(ohne Namen)'; En: '(without name)'),
    (De: '**In %s** ([Zeile %d](%s#L%d))'; En: '**In %s** ([line %d](%s#L%d))'),
    (De: ' … %d weitere'; En: ' … %d more'),
    (De: 'Bild, %d Bytes'; En: 'Image, %d bytes'),
    (De: ' (geerbt)'; En: ' (inherited)'),
    (De: '    Ereignisse: '; En: '    Events: '));

{$SCOPEDENUMS OFF}

function CountHexBytes(const AValue: string): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  for mIndex := 1 to Length(AValue) do
  begin
    if CharInSet(AValue[mIndex], ['0'..'9', 'A'..'F', 'a'..'f']) then
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

/// <summary>Liste "( … )": je Zeile ein Eintrag; nach TFormInfo.cMaxListLines gekürzt.</summary>
function ListText(const AValue: string): string;
var
  mLine: string;
  mItems: TArray<string>;
  mIndex: Integer;
begin
  mItems := nil;
  for mLine in SplitString(Copy(AValue, 2, Length(AValue) - 2), #10) do
  begin
    if Trim(mLine) <> '' then
    begin
      mItems := mItems + [Trim(mLine)];
    end;
  end;
  Result := '(';
  for mIndex := 0 to Min(Length(mItems), TFormInfo.cMaxListLines) - 1 do
  begin
    if mIndex > 0 then
    begin
      Result := Result + ' ';
    end;
    Result := Result + mItems[mIndex];
  end;
  if Length(mItems) > TFormInfo.cMaxListLines then
  begin
    Result := Result + cTexts[TFormInfoText.More].Fmt([Length(mItems) - TFormInfo.cMaxListLines]);
  end;
  Result := Result + ')';
end;

class function TFormInfo.ValueText(const AProperty: TDfmProperty): string;
var
  mValue: string;
begin
  mValue := Trim(AProperty.Value);
  if StartsStr('{', mValue) and IsPicture(AProperty.Name) then
  begin
    Result := cTexts[TFormInfoText.ImageBytes].Fmt([CountHexBytes(mValue)]);
  end
  else if StartsStr('{', mValue) then
  begin
    Result := cTexts[TFormInfoText.BinaryDataBytes].Fmt([CountHexBytes(mValue)]);
  end
  else if StartsStr('(', mValue) then
  begin
    Result := ListText(mValue);
  end
  else
  begin
    Result := Trim(StringReplace(StringReplace(mValue, #13, '', [rfReplaceAll]), #10, ' ', [rfReplaceAll]));
    if Length(Result) > cMaxValueLength then
    begin
      Result := Copy(Result, 1, cMaxValueLength - 3) + '...';
    end;
  end;
end;

procedure AddObject(ALines: TStrings; AObject: TDfmObject; ADepth: Integer);
var
  mIndent, mEvents: string;
  mProp: TDfmProperty;
  mChild: TDfmObject;
begin
  mIndent := StringOfChar(' ', ADepth * 2);
  if AObject.Kind = TDfmObjectKind.Item then
  begin
    ALines.Add(mIndent + '- item');
  end
  else
  begin
    ALines.Add(Format('%s- %s: %s%s', [mIndent, IfThen(AObject.Name <> '', AObject.Name,
      cTexts[TFormInfoText.WithoutName].Text),
      AObject.TypeName, IfThen(AObject.Kind = TDfmObjectKind.Inherited_, cTexts[TFormInfoText.InheritedText].Text,
        '')]));
  end;
  mEvents := '';
  for mProp in AObject.Properties do
  begin
    if mProp.IsEvent then
    begin
      mEvents := mEvents + IfThen(mEvents <> '', ', ', '') + mProp.Name + ' → ' + mProp.Value;
    end
    else
    begin
      ALines.Add(Format('%s    %s = %s', [mIndent, mProp.Name, TFormInfo.ValueText(mProp)]));
    end;
  end;
  if mEvents <> '' then
  begin
    ALines.Add(mIndent + cTexts[TFormInfoText.Events].Text + mEvents);
  end;
  for mChild in AObject.Children do
  begin
    AddObject(ALines, mChild, ADepth + 1);
  end;
end;

class function TFormInfo.Describe(const AFormText: string): string;
var
  mDocument: TDfmDocument;
  mLines: TStringList;
  mError: TDfmError;
begin
  mDocument := TDfmParser.Parse(AFormText);
  mLines := TStringList.Create;
  try
    if mDocument.Root = nil then
    begin
      mLines.Add(cTexts[TFormInfoText.NoFormFound].Text);
    end
    else
    begin
      AddObject(mLines, mDocument.Root, 0);
    end;
    for mError in mDocument.Errors do
    begin
      mLines.Add(cTexts[TFormInfoText.ErrorLine].Fmt([mError.Position.Line + 1, mError.Message]));
    end;
    Result := TrimRight(mLines.Text);
  finally
    mLines.Free;
    mDocument.Free;
  end;
end;


class function TFormInfo.ComponentMarkdown(AObject: TDfmObject; const AFormFile: string): string;
var
  mProp: TDfmProperty;
begin
  Result := cTexts[TFormInfoText.InLineL].Fmt([ExtractFileName(AFormFile), AObject.Range.StartPos.Line + 1,
    TDocumentUris.FromPath(AFormFile), AObject.Range.StartPos.Line + 1]);
  for mProp in AObject.Properties do
  begin
    if mProp.IsEvent then
    begin
      Result := Result + #10 + Format('- %s → `%s`', [mProp.Name, mProp.Value]);
    end
    else
    begin
      Result := Result + #10 + Format('- %s = `%s`', [mProp.Name, ValueText(mProp)]);
    end;
  end;
end;
function SearchByName(AObject: TDfmObject; const AName: string): TDfmObject;
var
  mChild: TDfmObject;
begin
  if SameText(AObject.Name, AName) then
  begin
    Exit(AObject);
  end;
  for mChild in AObject.Children do
  begin
    Result := SearchByName(mChild, AName);
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

class function TFormInfo.FieldMarkdown(const AFormText, AFormFile, AFormClass, AFieldName: string): string;
var
  mDocument: TDfmDocument;
  mObject: TDfmObject;
begin
  Result := '';
  if AFormText = '' then
  begin
    Exit;
  end;
  mDocument := TDfmParser.Parse(AFormText);
  try
    mObject := FindComponent(mDocument, AFormClass, AFieldName);
    if mObject <> nil then
    begin
      Result := ComponentMarkdown(mObject, AFormFile);
    end;
  finally
    mDocument.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Dfm.FormInfo', cTexts);

end.
