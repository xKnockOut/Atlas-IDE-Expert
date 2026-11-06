unit Atlas.Common.Lsp.IdeUnits.Source;

// Ersatz-Unit aus den Mitgliedern, die die IDE über die RTTI ihrer Packages kennt (atlas/ideMembers). Das
// Plugin meldet je Unit ohne Quelltext ihre Typen:
//   {"unit": "Vendor.Grid", "types": [
//     {"name": "TVendorGrid", "kind": "class", "parent": "Vcl.Controls.TCustomControl",
//      "interfaces": ["Vendor.Base.IVendor"], "members": [
//        {"kind": "property", "name": "State", "type": "Vendor.Grid.TGridState", "visibility": "published"},
//        {"kind": "function", "name": "Find", "type": "System.Integer", "static": true,
//         "params": [{"name": "AName", "type": "System.string", "flag": "const"}]}]},
//     {"name": "TGridState", "kind": "enum", "values": ["gsNone", "gsEdit"]}]}
// Daraus entsteht der interface-Teil einer Unit als Pascal-Text: Typnamen mit Unit-Präfix werden kurz
// geschrieben und ihre Units in uses aufgenommen. Der Index liest den Text wie jede andere Unit; so kennen
// Hover, Vervollständigung und Parameterhilfe die Mitglieder, ohne dass es den Quelltext gibt.
// Arten: class, interface, record, enum; andere Typen (Mengen, Zeiger, Aliase) entfallen.

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections;

type
  TIdeUnitSource = class abstract
  public
    /// <summary>Pascal-Text der Unit AUnit mit den Typen ATypes (Format oben).</summary>
    class function Build(const AUnit: string; ATypes: TJSONArray): string; static;
    /// <summary>ATypeText mit kurzen Namen (Vcl.Graphics.TColor → TColor, auch in TList&lt;A.B.TC&gt;); die
    /// Präfixe außer AUnit und System kommen nach AUses.</summary>
    class function ShortType(const ATypeText, AUnit: string; AUses: TList<string>): string; static;
  end;

implementation

const
  cIndent = '  ';
  cMemberIndent = '    ';

function IsIdentChar(AChar: Char; AFirst: Boolean): Boolean;
begin
  Result := CharInSet(AChar, ['A'..'Z', 'a'..'z', '_']) or (not AFirst and CharInSet(AChar, ['0'..'9']));
end;

/// <summary>Präfix einer Unit merken, außer der eigenen und System.</summary>
procedure AddUse(const APrefix, AUnit: string; AUses: TList<string>);
var
  mUse: string;
begin
  if SameText(APrefix, AUnit) or SameText(APrefix, 'System') then
  begin
    Exit;
  end;
  for mUse in AUses do
  begin
    if SameText(mUse, APrefix) then
    begin
      Exit;
    end;
  end;
  AUses.Add(APrefix);
end;

/// <summary>Bezeichnerkette ab AStart (A.B.C) bis vor AEnd.</summary>
function ChainEnd(const AText: string; AStart: Integer): Integer;
begin
  Result := AStart;
  while (Result <= Length(AText)) and (IsIdentChar(AText[Result], False) or
    ((AText[Result] = '.') and (Result < Length(AText)) and IsIdentChar(AText[Result + 1], True))) do
  begin
    Inc(Result);
  end;
end;

class function TIdeUnitSource.ShortType(const ATypeText, AUnit: string; AUses: TList<string>): string;
var
  mPos, mEnd, mDot: Integer;
  mChain: string;
begin
  Result := '';
  mPos := 1;
  while mPos <= Length(ATypeText) do
  begin
    if not IsIdentChar(ATypeText[mPos], True) then
    begin
      Result := Result + ATypeText[mPos];
      Inc(mPos);
      Continue;
    end;
    mEnd := ChainEnd(ATypeText, mPos);
    mChain := Copy(ATypeText, mPos, mEnd - mPos);
    mDot := LastDelimiter('.', mChain);
    if mDot > 0 then
    begin
      AddUse(Copy(mChain, 1, mDot - 1), AUnit, AUses);
    end;
    Result := Result + Copy(mChain, mDot + 1, MaxInt);
    mPos := mEnd;
  end;
end;

type
  /// <summary>Kontext beim Schreiben einer Unit: Text, Name und gesammelte uses.</summary>
  TSourceWriter = record
    Text: TStringBuilder;
    UnitName: string;
    Uses_: TList<string>;
    function Short(const ATypeText: string): string;
  end;

function TSourceWriter.Short(const ATypeText: string): string;
begin
  Result := TIdeUnitSource.ShortType(ATypeText, UnitName, Uses_);
end;

/// <summary>Parameterliste "(const A: T; var B)" aus "params"; '' ohne Parameter.</summary>
function ParamsText(var AWriter: TSourceWriter; AParams: TJSONArray; const AOpen, AClose: string): string;
var
  mValue: TJSONValue;
  mParam: TJSONObject;
  mFlag, mType, mPart: string;
begin
  Result := '';
  if (AParams = nil) or (AParams.Count = 0) then
  begin
    Exit;
  end;
  for mValue in AParams do
  begin
    if not (mValue is TJSONObject) then
    begin
      Continue;
    end;
    mParam := TJSONObject(mValue);
    mFlag := mParam.GetValue<string>('flag', '');
    mType := mParam.GetValue<string>('type', '');
    mPart := mParam.GetValue<string>('name', 'Value');
    if mFlag <> '' then
    begin
      mPart := mFlag + ' ' + mPart;
    end;
    if mType <> '' then
    begin
      mPart := mPart + ': ' + AWriter.Short(mType);
    end;
    if Result <> '' then
    begin
      Result := Result + '; ';
    end;
    Result := Result + mPart;
  end;
  if Result <> '' then
  begin
    Result := AOpen + Result + AClose;
  end;
end;

/// <summary>Kopf einer Methode: [class ]procedure|function|constructor|destructor Name(…)[: T];</summary>
function MethodText(var AWriter: TSourceWriter; AMember: TJSONObject; const AKind: string): string;
var
  mType: string;
begin
  Result := AKind + ' ' + AMember.GetValue<string>('name', '') +
    ParamsText(AWriter, AMember.GetValue<TJSONArray>('params', nil), '(', ')');
  mType := AMember.GetValue<string>('type', '');
  if SameText(AKind, 'function') and (mType <> '') then
  begin
    Result := Result + ': ' + AWriter.Short(mType);
  end;
  Result := Result + ';';
  if AMember.GetValue<Boolean>('static', False) and not SameText(AKind, 'constructor') and
    not SameText(AKind, 'destructor') then
  begin
    Result := 'class ' + Result;
  end;
end;

/// <summary>Zeile eines Mitglieds; '' für unbekannte Arten oder ohne Namen bzw. Typ.</summary>
function MemberText(var AWriter: TSourceWriter; AMember: TJSONObject): string;
var
  mKind, mName, mType: string;
begin
  Result := '';
  mKind := AMember.GetValue<string>('kind', '');
  mName := AMember.GetValue<string>('name', '');
  mType := AMember.GetValue<string>('type', '');
  if not IsValidIdent(mName) then
  begin
    Exit;
  end;
  if SameText(mKind, 'field') and (mType <> '') then
  begin
    Result := mName + ': ' + AWriter.Short(mType) + ';';
  end
  else if SameText(mKind, 'property') and (mType <> '') then
  begin
    Result := 'property ' + mName + ParamsText(AWriter, AMember.GetValue<TJSONArray>('index', nil), '[', ']') +
      ': ' + AWriter.Short(mType) + ';';
    if AMember.GetValue<Boolean>('default', False) then
    begin
      Result := Result + ' default;';
    end;
  end
  else if SameText(mKind, 'procedure') or SameText(mKind, 'function') or SameText(mKind, 'constructor') or
    SameText(mKind, 'destructor') then
  begin
    Result := MethodText(AWriter, AMember, LowerCase(mKind));
  end;
end;

const
  /// <summary>Abschnitte in der Reihenfolge der Ausgabe; Felder vor Methoden je Abschnitt.</summary>
  cVisibilities: array[0..2] of string = ('protected', 'public', 'published');

/// <summary>Mitglieder eines Abschnitts: zuerst Felder, dann der Rest.</summary>
procedure WriteSection(var AWriter: TSourceWriter; AMembers: TJSONArray; const AVisibility: string;
  AWithHeader: Boolean);
var
  mLines: TList<string>;
  mValue: TJSONValue;
  mMember: TJSONObject;
  mLine: string;
begin
  mLines := TList<string>.Create;
  try
    for mValue in AMembers do
    begin
      if not (mValue is TJSONObject) then
      begin
        Continue;
      end;
      mMember := TJSONObject(mValue);
      if not SameText(mMember.GetValue<string>('visibility', 'public'), AVisibility) then
      begin
        Continue;
      end;
      mLine := MemberText(AWriter, mMember);
      if mLine = '' then
      begin
        Continue;
      end;
      if SameText(mMember.GetValue<string>('kind', ''), 'field') then
      begin
        mLines.Insert(0, mLine);
      end
      else
      begin
        mLines.Add(mLine);
      end;
    end;
    if mLines.Count = 0 then
    begin
      Exit;
    end;
    if AWithHeader then
    begin
      AWriter.Text.Append(cIndent).Append(AVisibility).Append(sLineBreak);
    end;
    for mLine in mLines do
    begin
      AWriter.Text.Append(cMemberIndent).Append(mLine).Append(sLineBreak);
    end;
  finally
    mLines.Free;
  end;
end;

/// <summary>Vorfahr und Interfaces als "(TBase, IFoo)"; '' ohne.</summary>
function AncestorsText(var AWriter: TSourceWriter; AType: TJSONObject): string;
var
  mParent: string;
  mInterfaces: TJSONArray;
  mValue: TJSONValue;
begin
  Result := '';
  mParent := AType.GetValue<string>('parent', '');
  if mParent <> '' then
  begin
    Result := AWriter.Short(mParent);
  end;
  mInterfaces := AType.GetValue<TJSONArray>('interfaces', nil);
  if mInterfaces <> nil then
  begin
    for mValue in mInterfaces do
    begin
      if Result <> '' then
      begin
        Result := Result + ', ';
      end;
      Result := Result + AWriter.Short(mValue.Value);
    end;
  end;
  if Result <> '' then
  begin
    Result := '(' + Result + ')';
  end;
end;

/// <summary>Klasse, Interface oder Record mit Mitgliedern.</summary>
procedure WriteStructured(var AWriter: TSourceWriter; AType: TJSONObject; const AName, AKind: string);
var
  mMembers: TJSONArray;
  mVisibility: string;
  mHeaders: Boolean;
begin
  AWriter.Text.Append(cIndent).Append(AName).Append(' = ').Append(AKind);
  if not SameText(AKind, 'record') then
  begin
    AWriter.Text.Append(AncestorsText(AWriter, AType));
  end;
  AWriter.Text.Append(sLineBreak);
  mMembers := AType.GetValue<TJSONArray>('members', nil);
  // Interfaces kennen keine Abschnitte.
  mHeaders := not SameText(AKind, 'interface');
  if mMembers <> nil then
  begin
    for mVisibility in cVisibilities do
    begin
      WriteSection(AWriter, mMembers, mVisibility, mHeaders);
    end;
  end;
  AWriter.Text.Append(cIndent).Append('end;').Append(sLineBreak);
end;

/// <summary>Aufzählungstyp "TName = (a, b);"; nichts ohne Werte.</summary>
procedure WriteEnum(var AWriter: TSourceWriter; AType: TJSONObject; const AName: string);
var
  mValues: TJSONArray;
  mValue: TJSONValue;
  mNames: string;
begin
  mValues := AType.GetValue<TJSONArray>('values', nil);
  mNames := '';
  if mValues <> nil then
  begin
    for mValue in mValues do
    begin
      if IsValidIdent(mValue.Value) then
      begin
        if mNames <> '' then
        begin
          mNames := mNames + ', ';
        end;
        mNames := mNames + mValue.Value;
      end;
    end;
  end;
  if mNames <> '' then
  begin
    AWriter.Text.Append(cIndent).Append(AName).Append(' = (').Append(mNames).Append(');').Append(sLineBreak);
  end;
end;

procedure WriteType(var AWriter: TSourceWriter; AType: TJSONObject);
var
  mName, mKind: string;
begin
  mName := AType.GetValue<string>('name', '');
  mKind := LowerCase(AType.GetValue<string>('kind', ''));
  if not IsValidIdent(mName) then
  begin
    Exit;
  end;
  if mKind = 'enum' then
  begin
    WriteEnum(AWriter, AType, mName);
  end
  else if (mKind = 'class') or (mKind = 'interface') or (mKind = 'record') then
  begin
    WriteStructured(AWriter, AType, mName, mKind);
  end;
end;

class function TIdeUnitSource.Build(const AUnit: string; ATypes: TJSONArray): string;
var
  mWriter: TSourceWriter;
  mValue: TJSONValue;
  mHead: string;
begin
  mWriter.UnitName := AUnit;
  mWriter.Text := TStringBuilder.Create;
  mWriter.Uses_ := TList<string>.Create;
  try
    if ATypes <> nil then
    begin
      for mValue in ATypes do
      begin
        if mValue is TJSONObject then
        begin
          WriteType(mWriter, TJSONObject(mValue));
        end;
      end;
    end;
    mHead := 'unit ' + AUnit + ';' + sLineBreak + sLineBreak + 'interface' + sLineBreak + sLineBreak;
    if mWriter.Uses_.Count > 0 then
    begin
      mHead := mHead + 'uses' + sLineBreak + cIndent + string.Join(', ', mWriter.Uses_.ToArray) + ';' +
        sLineBreak + sLineBreak;
    end;
    if mWriter.Text.Length > 0 then
    begin
      mHead := mHead + 'type' + sLineBreak;
    end;
    Result := mHead + mWriter.Text.ToString + sLineBreak + 'implementation' + sLineBreak + sLineBreak + 'end.' +
      sLineBreak;
  finally
    mWriter.Uses_.Free;
    mWriter.Text.Free;
  end;
end;

end.
