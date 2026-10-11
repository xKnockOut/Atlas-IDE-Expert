unit Atlas.Common.Pascal.XmlDoc;

// ///-Dokumentation (XMLDoc) nach Abschnitten zerlegen (#405, #427): <summary>,
// <param name>, <returns>, <exception cref> und <remarks>. Innere Tags werden
// zu Text: <c>X</c> und <see cref="X"/> zu X, <paramref name="X"/> zu X,
// <para> zu einem Absatz; Entitäten (&lt; &gt; &amp; &quot;) werden aufgelöst.
// Ohne erkannte Abschnitte gilt der ganze Kommentar als Zusammenfassung.

interface

uses
  System.SysUtils;

type
  TXmlDocEntry = record
    /// <summary>Parametername bzw. Exception-Klasse.</summary>
    Name: string;
    Text: string;
  end;

  TXmlDoc = record
    Summary: string;
    Returns: string;
    Remarks: string;
    Params: TArray<TXmlDocEntry>;
    Exceptions: TArray<TXmlDocEntry>;
    function IsEmpty: Boolean;
    /// <summary>Zerlegt den XML-Text eines ///-Kommentars (ohne die ///).</summary>
    class function Parse(const AXml: string): TXmlDoc; static;
    /// <summary>Text der ///-Zeilen direkt über ALine (0-basiert), ohne ///; Attribute ([...])
    /// dazwischen werden übersprungen.</summary>
    class function CommentAbove(const ALines: TArray<string>; ALine: Integer): string; static;
    /// <summary>Innere Tags zu Text, Leerraum zusammengefasst; Absätze bleiben als #10.</summary>
    class function CleanText(const AText: string): string; static;
  end;

implementation

uses
  System.StrUtils,
  System.RegularExpressions;

const
  Options = [roIgnoreCase, roSingleLine];

{ TXmlDoc }

function TXmlDoc.IsEmpty: Boolean;
begin
  Result := (Summary = '') and (Returns = '') and (Remarks = '') and (Length(Params) = 0) and
    (Length(Exceptions) = 0);
end;

class function TXmlDoc.CleanText(const AText: string): string;
var
  Text: string;
  Paragraphs: TArray<string>;
  Index: Integer;
begin
  Text := AText;
  // <see cref="X">Y</see> → Y, <see cref="X"/> → X, <paramref name="X"/> → X, <c>X</c> → X.
  Text := TRegEx.Replace(Text, '<see\s+cref\s*=\s*"([^"]*)"\s*>(.*?)</see>', '$2', Options);
  Text := TRegEx.Replace(Text, '<(see|seealso)\s+cref\s*=\s*"([^"]*)"\s*/>', '$2', Options);
  Text := TRegEx.Replace(Text, '<(paramref|typeparamref)\s+name\s*=\s*"([^"]*)"\s*/>', '$2', Options);
  Text := TRegEx.Replace(Text, '<para\s*/?>|</para>|<br\s*/?>', #10, Options);
  Text := TRegEx.Replace(Text, '<[^>]+>', '', Options);
  Text := StringReplace(Text, '&lt;', '<', [rfReplaceAll]);
  Text := StringReplace(Text, '&gt;', '>', [rfReplaceAll]);
  Text := StringReplace(Text, '&quot;', '"', [rfReplaceAll]);
  Text := StringReplace(Text, '&amp;', '&', [rfReplaceAll]);
  // Zeilenumbrüche des Kommentars sind Fließtext; nur <para> trennt Absätze.
  Paragraphs := Text.Split([#10]);
  Result := '';
  for Index := 0 to High(Paragraphs) do
  begin
    Text := Trim(TRegEx.Replace(Paragraphs[Index], '\s+', ' '));
    if Text = '' then
      Continue;
    if Result <> '' then
      Result := Result + #10;
    Result := Result + Text;
  end;
end;

class function TXmlDoc.Parse(const AXml: string): TXmlDoc;
var
  Match: TMatch;
  Entry: TXmlDocEntry;
  Xml: string;
begin
  Result := Default(TXmlDoc);
  // Zeilenumbrüche im Kommentar trennen keine Absätze.
  Xml := StringReplace(StringReplace(AXml, #13#10, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]);
  Match := TRegEx.Match(Xml, '<summary>(.*?)</summary>', Options);
  if Match.Success then
    Result.Summary := CleanText(Match.Groups[1].Value);
  Match := TRegEx.Match(Xml, '<returns>(.*?)</returns>', Options);
  if Match.Success then
    Result.Returns := CleanText(Match.Groups[1].Value);
  Match := TRegEx.Match(Xml, '<remarks>(.*?)</remarks>', Options);
  if Match.Success then
    Result.Remarks := CleanText(Match.Groups[1].Value);
  for Match in TRegEx.Matches(Xml, '<param\s+name\s*=\s*"([^"]*)"\s*>(.*?)</param>', Options) do
  begin
    Entry.Name := Match.Groups[1].Value;
    Entry.Text := CleanText(Match.Groups[2].Value);
    Result.Params := Result.Params + [Entry];
  end;
  for Match in TRegEx.Matches(Xml, '<exception\s+cref\s*=\s*"([^"]*)"\s*>(.*?)</exception>', Options) do
  begin
    Entry.Name := Match.Groups[1].Value;
    Entry.Text := CleanText(Match.Groups[2].Value);
    Result.Exceptions := Result.Exceptions + [Entry];
  end;
  // Kommentar ohne Abschnitte: als Ganzes die Zusammenfassung.
  if Result.IsEmpty then
    Result.Summary := CleanText(Xml);
end;

class function TXmlDoc.CommentAbove(const ALines: TArray<string>; ALine: Integer): string;
var
  Index: Integer;
  Line: string;
begin
  Result := '';
  Index := ALine - 1;
  while (Index >= 0) and (Index <= High(ALines)) do
  begin
    Line := Trim(ALines[Index]);
    if StartsStr('///', Line) then
    begin
      Line := Copy(Line, 4, MaxInt);
      if Result = '' then
        Result := Line
      else
        Result := Line + #10 + Result;
    end
    else if not StartsStr('[', Line) then
      Break;
    Dec(Index);
  end;
end;

end.
