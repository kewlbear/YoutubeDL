#!/bin/sh
mkdir -p "$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/Library/Python"
mkdir -p "$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/Library/Application Support/com.example.helloworld"
rsync -pvtrL --exclude .hg --exclude .svn --exclude .git "$PROJECT_DIR/Support/Python/Resources/lib" "$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/Library/Python"
rsync -pvtrL --exclude .hg --exclude .svn --exclude .git "$PROJECT_DIR/helloworld/app" "$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/Library/Application Support/com.example.helloworld"
rsync -pvtrL --exclude .hg --exclude .svn --exclude .git "$PROJECT_DIR/helloworld/app_packages" "$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/Library/Application Support/com.example.helloworld"
