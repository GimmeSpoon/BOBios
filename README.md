# BOBios

## Book cover detection on book shelves project


* 빌드 시 반드시 MLKit 구동을 위해 pod 으로 라이브러리 설치 필요 [**Link**](https://developers.google.com/ml-kit/vision/text-recognition/ios) 



1. cocoadpods 설치
2. 생성되는 podfile에 다음 코드 추가
  *****
  pod 'GoogleMLKit/TextRecognition'
  *****
3. shell에서 'pod install' 입력
4. 이후 .xcworkspace 를 xcode로 열어서 빌드
