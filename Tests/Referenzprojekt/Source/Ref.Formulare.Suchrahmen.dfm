object Suchrahmen: TSuchrahmen
  Left = 0
  Top = 0
  Width = 320
  Height = 33
  TabOrder = 0
  object SuchEdit: TEdit
    Left = 4
    Top = 4
    Width = 220
    Height = 23
    TabOrder = 0
  end
  object SuchenButton: TButton
    Left = 232
    Top = 3
    Width = 75
    Height = 25
    Caption = 'Suchen'
    TabOrder = 1
    OnClick = SuchenButtonClick
  end
end
