//
//  ShaderTypes.h
//  YD
//
//  Created by 안창범 on 2020/09/08.
//  Copyright © 2020 Kewlbear. All rights reserved.
//

#ifndef ShaderTypes_h
#define ShaderTypes_h

typedef enum VertexAttributes {
    kVertexAttributePosition  = 0,
    kVertexAttributeTexcoord  = 1,
    kVertexAttributeNormal    = 2
} VertexAttributes;

typedef enum TextureIndices {
    kTextureIndexY,
    kTextureIndexCb,
    kTextureIndexCr,
} TextureIndices;

#endif /* ShaderTypes_h */
